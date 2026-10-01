# Helpers for the Quarto analytical briefing.
# All reported values are derived from the validated outputs of analysis.R.

brief_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

fmt_rate <- function(value) {
  format(round(value), big.mark = ",", scientific = FALSE, trim = TRUE)
}

fmt_pct <- function(value, signed = FALSE) {
  pattern <- if (signed) "%+.1f%%" else "%.1f%%"
  sprintf(pattern, value)
}

fmt_pp <- function(value) {
  sprintf("%+.1f pp", value)
}

read_briefing_csv <- function(path, required_columns) {
  brief_assert(file.exists(path), paste("Missing briefing input:", path))
  data <- readr::read_csv(path, show_col_types = FALSE)
  missing_columns <- setdiff(required_columns, names(data))
  brief_assert(
    length(missing_columns) == 0L,
    paste("Missing columns in", basename(path), ":",
          paste(missing_columns, collapse = ", "))
  )
  data
}

prepare_briefing <- function(results_dir = "results") {
  changes <- read_briefing_csv(
    file.path(results_dir, "percentage_changes.csv"),
    c("region", "service", "baseline_rate", "latest_rate",
      "five_year_change_pct", "latest_annual_change_pct")
  )
  latest <- read_briefing_csv(
    file.path(results_dir, "latest_regional_comparison.csv"),
    c("region", "financial_year", "service", "rate_per_10000",
      "annual_change_pct")
  )
  ranges <- read_briefing_csv(
    file.path(results_dir, "regional_range_summary.csv"),
    c("service", "regional_range_2018", "regional_range_2023", "direction")
  )
  review <- read_briefing_csv(
    file.path(results_dir, "operational_review_prompts.csv"),
    c("region", "community_change_pct", "ed_change_pct",
      "hospitalisation_change_pct", "ed_minus_community_pp",
      "hospital_minus_community_pp", "operational_review_prompt")
  )

  expected_regions <- c("Gippsland", "Murray", "Western Victoria")
  expected_services <- c(
    "Community contacts", "ED presentations", "Hospitalisations"
  )
  brief_assert(
    setequal(unique(changes$region), expected_regions),
    "Briefing inputs do not contain the expected PHNs."
  )
  brief_assert(
    setequal(unique(changes$service), expected_services),
    "Briefing inputs do not contain the expected service indicators."
  )
  brief_assert(nrow(changes) == 9L, "Expected nine five-year comparison rows.")
  brief_assert(nrow(latest) == 9L, "Expected nine latest-rate rows.")
  brief_assert(nrow(review) == 3L, "Expected three operational-review rows.")

  community <- dplyr::filter(changes, service == "Community contacts")
  ed <- dplyr::filter(changes, service == "ED presentations")
  hospital <- dplyr::filter(changes, service == "Hospitalisations")

  largest_community <- dplyr::slice_max(
    community, five_year_change_pct, n = 1, with_ties = FALSE
  )
  smallest_community <- dplyr::slice_min(
    community, five_year_change_pct, n = 1, with_ties = FALSE
  )
  largest_ed_decrease <- dplyr::slice_min(
    ed, five_year_change_pct, n = 1, with_ties = FALSE
  )
  largest_hospital_increase <- dplyr::slice_max(
    hospital, five_year_change_pct, n = 1, with_ties = FALSE
  )
  largest_latest_ed <- dplyr::slice_max(
    review, ed_change_pct, n = 1, with_ties = FALSE
  )

  latest_leaders <- latest |>
    dplyr::group_by(service) |>
    dplyr::slice_max(rate_per_10000, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  leader_for <- function(service_name) {
    dplyr::filter(latest_leaders, service == service_name)
  }

  metrics <- list(
    largest_community = largest_community,
    smallest_community = smallest_community,
    largest_ed_decrease = largest_ed_decrease,
    largest_hospital_increase = largest_hospital_increase,
    largest_latest_ed = largest_latest_ed,
    community_min_change = min(community$five_year_change_pct),
    community_max_change = max(community$five_year_change_pct),
    hospital_min_change = min(hospital$five_year_change_pct),
    hospital_max_change = max(hospital$five_year_change_pct),
    all_ed_rates_lower = all(ed$latest_rate < ed$baseline_rate),
    community_range = dplyr::filter(
      ranges, service == "Community contacts"
    )$regional_range_2023,
    community_leader = leader_for("Community contacts"),
    ed_leader = leader_for("ED presentations"),
    hospital_leader = leader_for("Hospitalisations")
  )

  brief_assert(
    length(metrics$community_range) == 1L,
    "Expected one community-contact regional range."
  )
  brief_assert(
    metrics$all_ed_rates_lower,
    "Expected all latest ED rates to be below their five-year baselines."
  )

  list(
    changes = changes,
    latest = latest,
    ranges = ranges,
    review = review,
    metrics = metrics
  )
}

community_change_summary <- function(briefing) {
  low <- briefing$metrics$smallest_community
  high <- briefing$metrics$largest_community
  sprintf(
    "Five-year growth ranged from %s in %s to %s in %s.",
    fmt_pct(low$five_year_change_pct), low$region,
    fmt_pct(high$five_year_change_pct), high$region
  )
}

latest_profile_summary <- function(briefing) {
  community <- briefing$metrics$community_leader
  ed <- briefing$metrics$ed_leader
  hospital <- briefing$metrics$hospital_leader
  if (community$region == ed$region) {
    sprintf(
      "%s recorded the highest latest community-contact and ED rates; %s recorded the highest hospitalisation rate.",
      community$region, hospital$region
    )
  } else {
    sprintf(
      "%s recorded the highest community-contact rate; %s recorded the highest ED rate; and %s recorded the highest hospitalisation rate.",
      community$region, ed$region, hospital$region
    )
  }
}

latest_profile_rates <- function(briefing) {
  community <- briefing$metrics$community_leader
  ed <- briefing$metrics$ed_leader
  hospital <- briefing$metrics$hospital_leader
  if (community$region == ed$region) {
    sprintf(
      "%s recorded the highest community-contact rate (%s) and ED presentation rate (%s) per 10,000. %s recorded the highest hospitalisation rate (%s).",
      community$region, fmt_rate(community$rate_per_10000),
      fmt_rate(ed$rate_per_10000), hospital$region,
      fmt_rate(hospital$rate_per_10000)
    )
  } else {
    sprintf(
      "%s recorded the highest community-contact rate (%s), %s the highest ED presentation rate (%s), and %s the highest hospitalisation rate (%s) per 10,000.",
      community$region, fmt_rate(community$rate_per_10000),
      ed$region, fmt_rate(ed$rate_per_10000), hospital$region,
      fmt_rate(hospital$rate_per_10000)
    )
  }
}

latest_rate_table <- function(briefing) {
  briefing$latest |>
    dplyr::select(
      PHN = region,
      Indicator = service,
      `Rate per 10,000` = rate_per_10000
    )
}

operational_review_table <- function(briefing) {
  briefing$review |>
    dplyr::transmute(
      PHN = region,
      Community = fmt_pct(community_change_pct),
      ED = fmt_pct(ed_change_pct),
      Hospital = fmt_pct(hospitalisation_change_pct),
      `ED minus community` = fmt_pp(ed_minus_community_pp)
    )
}
