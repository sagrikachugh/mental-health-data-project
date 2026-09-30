# Victorian regional mental-health service utilisation
# Purpose: produce a reproducible briefing on trends in community contacts,
# emergency department presentations and hospitalisations.
# Run from the project folder with: Rscript analysis.R

# 1. Setup -----------------------------------------------------------------
required_packages <- c("dplyr", "tidyr", "ggplot2", "readr", "scales")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Install required packages: ", paste(missing_packages, collapse = ", "),
       call. = FALSE)
}
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
if (!dir.exists("data/raw")) {
  stop("Run analysis.R from the mental-health-data-project folder.", call. = FALSE)
}
dir.create("figures", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

regions <- c("Gippsland", "Murray", "Western Victoria")
services <- c("Community contacts", "ED presentations", "Hospitalisations")
years <- 2018:2023
topic_map <- c(
  "Community care contacts" = "Community contacts",
  "Emergency department presentations" = "ED presentations",
  "Admitted patient care hospitalisations" = "Hospitalisations"
)
measure_map <- c(
  "Community care contacts" = "Contacts",
  "Emergency department presentations" = "Presentations",
  "Admitted patient care hospitalisations" = "Hospitalisations"
)
raw_files <- file.path(
  "data/raw", paste0(tolower(gsub(" ", "_", regions)), ".csv")
)
assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}
assert(all(file.exists(raw_files)), "One or more AIHW source exports are missing.")

# 2. Read and validate source data -----------------------------------------
read_aihw_export <- function(path, expected_region) {
  # Tableau labels these files CSV, but they are UTF-16LE, tab-separated
  # crosstabs with source notes above the data header.
  lines <- readLines(file(path, encoding = "UTF-16LE"), warn = FALSE)
  header_row <- grep("^Row\tYear\tTopics\t", lines)
  assert(length(header_row) == 1L,
         paste("Could not identify one data header in", basename(path)))

  preamble <- trimws(lines[seq_len(header_row - 1L)])
  assert(expected_region %in% preamble,
         paste("Region label does not match", basename(path)))
  assert("PHN" %in% preamble, paste("Expected PHN geography in", basename(path)))

  source <- read.delim(
    text = paste(lines[header_row:length(lines)], collapse = "\n"),
    sep = "\t", colClasses = "character", check.names = FALSE,
    quote = "", comment.char = "", na.strings = character()
  )
  assert(ncol(source) == 8L, paste("Unexpected schema in", basename(path)))
  names(source)[8] <- "raw_value" # Tableau inserts a footnote as this header.

  selected <- source[
    source$Topics %in% names(topic_map) & source[["Age Group"]] == "Total",
  ]
  assert(all(selected$Metric == "Rate per 10,000 population"),
         paste("Unexpected metric in", basename(path)))
  assert(all(trimws(selected$Practitioner) == ""),
         paste("Unexpected practitioner split in", basename(path)))
  assert(all(selected$Measure == unname(measure_map[selected$Topics])),
         paste("Unexpected measure in", basename(path)))

  clean_value <- gsub(",", "", trimws(selected$raw_value))
  publication_status <- ifelse(
    clean_value %in% c("n.p.", "n.a.", ""), clean_value, "published"
  )
  unexpected_value <- publication_status == "published" &
    !grepl("^[0-9]+(\\.[0-9]+)?$", clean_value)
  assert(!any(unexpected_value), paste("Unexpected value in", basename(path)))

  tibble(
    region = expected_region,
    geography = "PHN",
    financial_year = selected$Year,
    year = as.integer(substr(selected$Year, 1, 4)),
    service = unname(topic_map[selected$Topics]),
    age_group = "Total",
    rate_per_10000 = suppressWarnings(as.numeric(clean_value)),
    raw_value = selected$raw_value,
    publication_status = publication_status,
    source_file = basename(path)
  )
}

service_data <- bind_rows(Map(read_aihw_export, raw_files, regions)) |>
  arrange(region, service, year)
expected_panel <- expand_grid(region = regions, service = services, year = years)
validation_checks <- tibble(
  check = c(
    "54 expected observations",
    "Unique region-service-year keys",
    "Complete 3-region x 3-service x 6-year panel",
    "All selected all-age rates published",
    "All rates finite and non-negative",
    "Positive 2018-19 baseline for percentage changes"
  ),
  passed = c(
    nrow(service_data) == 54L,
    !anyDuplicated(service_data[c("region", "service", "year")]),
    nrow(anti_join(expected_panel, service_data,
                   by = c("region", "service", "year"))) == 0L,
    all(service_data$publication_status == "published"),
    all(is.finite(service_data$rate_per_10000) &
          service_data$rate_per_10000 >= 0),
    all(service_data$rate_per_10000[service_data$year == min(years)] > 0)
  )
)
readr::write_csv(validation_checks, "results/validation_checks.csv")
assert(all(validation_checks$passed),
       "Validation failed. Review results/validation_checks.csv.")

# 3. Descriptive analysis --------------------------------------------------
service_data <- service_data |>
  group_by(region, service) |>
  arrange(year, .by_group = TRUE) |>
  mutate(
    index_2018_19 = 100 * rate_per_10000 / first(rate_per_10000),
    annual_change_pct = if_else(
      lag(rate_per_10000) > 0,
      100 * (rate_per_10000 / lag(rate_per_10000) - 1),
      NA_real_
    )
  ) |>
  ungroup()

five_year_change <- service_data |>
  group_by(region, service) |>
  summarise(
    baseline_rate = first(rate_per_10000),
    latest_rate = last(rate_per_10000),
    rate_change = latest_rate - baseline_rate,
    five_year_change_pct = 100 * (latest_rate / baseline_rate - 1),
    latest_annual_change_pct = last(annual_change_pct),
    .groups = "drop"
  )
latest_rates <- service_data |>
  filter(year == max(years)) |>
  select(region, financial_year, service, rate_per_10000, annual_change_pct)

# Answers "which PHN changed most?" for each indicator.
largest_change <- five_year_change |>
  group_by(service) |>
  slice_max(abs(five_year_change_pct), n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(
    service, region,
    direction = if_else(five_year_change_pct >= 0, "Increase", "Decrease"),
    five_year_change_pct = round(five_year_change_pct, 1)
  )

# Tests whether the range across three regional PHNs widened or narrowed.
annual_regional_range <- service_data |>
  group_by(service, year) |>
  summarise(
    lowest_rate = min(rate_per_10000),
    highest_rate = max(rate_per_10000),
    regional_range = highest_rate - lowest_rate,
    relative_range_pct = 100 * regional_range / mean(rate_per_10000),
    .groups = "drop"
  )
regional_range_summary <- annual_regional_range |>
  filter(year %in% range(years)) |>
  select(service, year, regional_range, relative_range_pct) |>
  pivot_wider(
    names_from = year,
    values_from = c(regional_range, relative_range_pct),
    names_glue = "{.value}_{year}"
  ) |>
  mutate(
    range_change = regional_range_2023 - regional_range_2018,
    relative_range_change_pp = relative_range_pct_2023 - relative_range_pct_2018,
    direction = if_else(relative_range_change_pp > 0, "Widened", "Narrowed")
  )

# Compares acute and community growth. This is a monitoring prompt only;
# the data do not link patients across care settings.
growth_comparison <- five_year_change |>
  select(region, service, five_year_change_pct, latest_annual_change_pct) |>
  pivot_wider(
    names_from = service,
    values_from = c(five_year_change_pct, latest_annual_change_pct)
  )
names(growth_comparison) <- gsub(" ", "_", names(growth_comparison))
growth_comparison <- growth_comparison |>
  mutate(
    five_year_ed_gap_pp = five_year_change_pct_ED_presentations -
      five_year_change_pct_Community_contacts,
    five_year_hospital_gap_pp = five_year_change_pct_Hospitalisations -
      five_year_change_pct_Community_contacts,
    latest_ed_gap_pp = latest_annual_change_pct_ED_presentations -
      latest_annual_change_pct_Community_contacts,
    latest_hospital_gap_pp = latest_annual_change_pct_Hospitalisations -
      latest_annual_change_pct_Community_contacts,
    operational_review_prompt = latest_ed_gap_pp > 0 & latest_hospital_gap_pp > 0
  )
operational_review <- growth_comparison |>
  transmute(
    region,
    community_change_pct = round(latest_annual_change_pct_Community_contacts, 1),
    ed_change_pct = round(latest_annual_change_pct_ED_presentations, 1),
    hospitalisation_change_pct = round(latest_annual_change_pct_Hospitalisations, 1),
    ed_minus_community_pp = round(latest_ed_gap_pp, 1),
    hospital_minus_community_pp = round(latest_hospital_gap_pp, 1),
    operational_review_prompt,
    suggested_question = paste(
      "What changed in demand, acuity, access, capacity, pathways or coding",
      "between 2022-23 and 2023-24?"
    )
  )

# 4. Export briefing tables ------------------------------------------------
readr::write_csv(service_data, "data/victorian_phn_rates.csv")
readr::write_csv(
  five_year_change |> mutate(across(where(is.numeric), ~ round(.x, 1))),
  "results/percentage_changes.csv"
)
readr::write_csv(
  latest_rates |> mutate(across(where(is.numeric), ~ round(.x, 1))),
  "results/latest_regional_comparison.csv"
)
readr::write_csv(largest_change, "results/largest_change_by_indicator.csv")
readr::write_csv(
  regional_range_summary |> mutate(across(where(is.numeric), ~ round(.x, 1))),
  "results/regional_range_summary.csv"
)
readr::write_csv(operational_review, "results/operational_review_prompts.csv")

# 5. Briefing figures ------------------------------------------------------
# Colour-blind-safe palette. Figure 1 also uses line type so colour is not the
# only means of distinguishing the indicators.
service_colours <- c(
  "Community contacts" = "#0072B2",
  "ED presentations" = "#D55E00",
  "Hospitalisations" = "#7B3294"
)
service_line_types <- c(
  "Community contacts" = "solid",
  "ED presentations" = "dashed",
  "Hospitalisations" = "dotdash"
)
region_order <- c("Gippsland", "Murray", "Western Victoria")
source_note <- paste(
  "Source: AIHW Regional profiles;",
  "all-age crude rates per 10,000."
)
briefing_theme <- function() {
  theme_minimal(base_size = 12, base_family = "sans") +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_blank(),
      plot.title = element_text(
        face = "bold", size = 18, colour = "#17324D", margin = margin(b = 6)
      ),
      plot.subtitle = element_text(
        size = 11.5, colour = "#334E68", margin = margin(b = 14)
      ),
      plot.caption = element_text(
        hjust = 0, size = 8.5, colour = "#52616B", margin = margin(t = 12)
      ),
      strip.text = element_text(face = "bold", size = 11.5, colour = "#17324D"),
      axis.title = element_text(colour = "#243B53"),
      axis.text = element_text(colour = "#486581"),
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.text = element_text(size = 10.5),
      plot.margin = margin(18, 22, 16, 18),
      panel.spacing = unit(18, "pt")
    )
}
save_figure <- function(filename, plot, width, height) {
  ggsave(file.path("figures", paste0(filename, ".png")), plot,
         width = width, height = height, dpi = 300, bg = "white")
  ggsave(file.path("figures", paste0(filename, ".pdf")), plot,
         width = width, height = height, device = "pdf", bg = "white")
}
plot_data <- service_data |>
  mutate(
    region = factor(region, levels = region_order),
    service = factor(service, levels = services)
  )

# Figure 1: How has the mix of service activity changed?
figure_1 <- ggplot(
  plot_data,
  aes(year, index_2018_19, colour = service, linetype = service, group = service)
) +
  geom_hline(yintercept = 100, colour = "#9FB3C8", linetype = "dotted") +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  facet_wrap(~region, ncol = 3) +
  scale_colour_manual(values = service_colours) +
  scale_linetype_manual(values = service_line_types) +
  scale_x_continuous(breaks = c(2018, 2023), labels = c("2018-19", "2023-24")) +
  labs(
    title = "Community activity grew while acute activity was broadly stable",
    subtitle = "Indexed rates show change within each PHN; 2018-19 = 100",
    x = NULL, y = "Rate index",
    caption = paste(source_note, "The index compares change, not activity volumes.")
  ) +
  briefing_theme()
save_figure("01_indexed_trends", figure_1, 12, 7)

# Figure 2: Which PHNs reported the highest latest rates?
latest_plot_data <- latest_rates |>
  mutate(service = factor(service, levels = services)) |>
  arrange(service, rate_per_10000) |>
  mutate(region_service = factor(
    paste(service, region, sep = "___"),
    levels = paste(service, region, sep = "___")
  ))
figure_2 <- ggplot(
  latest_plot_data,
  aes(rate_per_10000, region_service, fill = service)
) +
  geom_col(width = 0.58, show.legend = FALSE) +
  geom_text(
    aes(label = scales::comma(rate_per_10000, accuracy = 1)),
    hjust = -0.18, size = 3.8, colour = "#17324D"
  ) +
  facet_wrap(~service, scales = "free", nrow = 1) +
  scale_fill_manual(values = service_colours) +
  scale_y_discrete(labels = function(x) sub(".*___", "", x)) +
  scale_x_continuous(
    labels = scales::label_comma(), expand = expansion(mult = c(0, 0.22))
  ) +
  labs(
    title = "Latest utilisation rates vary across regional PHNs",
    subtitle = "2023-24 rates, ranked within each measure; panels use different scales",
    x = "Rate per 10,000 population", y = NULL,
    caption = paste(source_note, "Higher rates may reflect need, access, capacity or coding.")
  ) +
  briefing_theme() +
  theme(panel.grid.major.x = element_line(colour = "#E6ECF0"))
save_figure("02_latest_rates", figure_2, 12, 6)

# Figure 3: Which region and indicator changed most?
heatmap_data <- five_year_change |>
  mutate(
    region = factor(region, levels = rev(region_order)),
    service = factor(service, levels = services),
    change_label = sprintf("%+.1f%%", five_year_change_pct)
  )
figure_3 <- ggplot(heatmap_data, aes(service, region, fill = five_year_change_pct)) +
  geom_tile(colour = "white", linewidth = 2) +
  geom_text(aes(label = change_label), size = 4.5, colour = "#102A43") +
  scale_fill_gradient2(
    low = "#E69F00", mid = "#F4F6F8", high = "#56B4E9",
    midpoint = 0, limits = c(-40, 40), guide = "none"
  ) +
  labs(
    title = "Community-contact rates recorded the largest five-year increases",
    subtitle = "Percentage change in rate per 10,000 population, 2018-19 to 2023-24",
    x = NULL, y = NULL,
    caption = paste(source_note, "Colour shows direction and magnitude, not performance quality.")
  ) +
  briefing_theme() +
  theme(panel.grid = element_blank(), axis.text.x = element_text(face = "bold"))
save_figure("03_percentage_change", figure_3, 10, 6)

# Figure 4: Where did acute activity outpace community contacts last year?
gap_plot_data <- growth_comparison |>
  select(region, latest_ed_gap_pp, latest_hospital_gap_pp) |>
  pivot_longer(-region, names_to = "service", values_to = "growth_gap_pp") |>
  mutate(
    service = recode(
      service,
      latest_ed_gap_pp = "ED presentations",
      latest_hospital_gap_pp = "Hospitalisations"
    ),
    service = factor(service, levels = c("ED presentations", "Hospitalisations")),
    region = factor(region, levels = rev(region_order))
  )
figure_4 <- ggplot(gap_plot_data, aes(growth_gap_pp, region, fill = service)) +
  geom_vline(xintercept = 0, colour = "#829AB1", linewidth = 0.6) +
  geom_col(position = position_dodge(width = 0.72), width = 0.62) +
  geom_text(
    aes(label = sprintf("%+.1f pp", growth_gap_pp)),
    position = position_dodge(width = 0.72),
    hjust = -0.15, size = 3.7, colour = "#17324D"
  ) +
  scale_fill_manual(values = service_colours[c("ED presentations", "Hospitalisations")]) +
  scale_x_continuous(
    labels = function(x) paste0(x, " pp"), expand = expansion(mult = c(0, 0.2))
  ) +
  labs(
    title = "Latest-year growth gap",
    subtitle = "Acute-care growth minus community-contact growth, 2022-23 to 2023-24",
    x = "Difference in percentage-point growth", y = NULL,
    caption = paste(
      source_note,
      "Positive values identify an operational question, not a performance threshold."
    )
  ) +
  briefing_theme() +
  theme(panel.grid.major.x = element_line(colour = "#E6ECF0"))
save_figure("04_recent_growth_gap", figure_4, 11, 6)

# 6. Reproducibility record ------------------------------------------------
capture.output(sessionInfo(), file = "results/session_info.txt")
message("Complete: validated data, six briefing tables and four figures created.")
