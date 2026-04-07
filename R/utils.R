# utils.R
# ------------------------------------------------------------------
# Function: build_variable_dictionary
# Purpose:  Summarize variables in a data frame for exploration or 
#           documentation purposes. Provides type, missingness, 
#           unique values, sample values, and optional flags for 
#           calculated/design/weight variables.
#
# Inputs:
#   df           - Data frame to summarize
#   labels_dict  - (Optional) Named list of variable labels to override 
#                  attributes in df
#   sample_n     - Number of sample values to display per variable
#   include_flags- Logical; if TRUE, includes flags for calculated (_),
#                  weight (WT), and design (_PSU/_STSTR) variables
#
# Outputs:
#   A data frame with one row per variable, containing:
#     variable       : Column name
#     label          : Variable label (from attribute or labels_dict)
#     dtype          : R class of the variable
#     n_missing      : Count of missing values
#     pct_missing    : Fraction of missing values
#     n_unique       : Number of unique (non-missing) values
#     sample_values  : Sample of unique values (comma-separated)
#     is_calculated  : Flag if variable appears calculated (starts with "_")
#     is_weight      : Flag if variable is a survey weight (contains "WT")
#     is_design_var  : Flag if variable is a design variable (_PSU, _STSTR)
# ------------------------------------------------------------------

build_variable_dictionary <- function(
    df,
    sample_n = 5,
    include_flags = TRUE
) {
  
  n_rows <- nrow(df)
  
  # Iterate over each column to calculate summary statistics
  records <- lapply(names(df), function(col) {
    
    series <- df[[col]]
    
    n_missing <- sum(is.na(series))
    pct_missing <- if (n_rows > 0) n_missing / n_rows else NA
    n_unique <- dplyr::n_distinct(series, na.rm = TRUE)
    
    # Grab a small sample of unique values for inspection
    sample_vals <- head(unique(series[!is.na(series)]), sample_n)
    sample_vals_str <- paste(as.character(sample_vals), collapse = ", ")
    
    # Determine label from attribute
    label <- attr(series, "label")
    if (is.null(label)) label <- NA
    
    # Optional flags for survey or calculated variables
    is_calculated <- if (include_flags) startsWith(col, "_") else NA
    is_weight <- if (include_flags) grepl("WT", toupper(col)) else NA
    is_design <- if (include_flags) col %in% c("_PSU", "_STSTR") else NA
    
    # Return a one-row data frame for this variable
    data.frame(
      variable = col,
      label = label,
      dtype = class(series)[1],
      n_missing = n_missing,
      pct_missing = round(pct_missing, 4),
      n_unique = n_unique,
      sample_values = sample_vals_str,
      is_calculated = is_calculated,
      is_weight = is_weight,
      is_design_var = is_design,
      stringsAsFactors = FALSE
    )
  })
  
  # Combine individual variable summaries into one data frame
  var_df <- do.call(rbind, records)
  
  # Sort variables: calculated first, then by descending missing fraction
  dplyr::arrange(
    var_df,
    is_calculated,
    dplyr::desc(pct_missing)
  )
}

# ------------------------------------------------------------------
# Function: analyze_survey_var
# Purpose: Compute weighted mean, SE, and 95% CI for a survey variable,
#          optionally grouped, and safely handle "lonely" PSUs.
#
# Inputs:
#   var_name        - Name of variable to analyze (string)
#   design          - Survey design object (svydesign)
#   na_codes        - Vector of values to treat as missing (default: c(9, NA))
#   group           - Optional grouping variable (string)
#   label_map       - Optional named vector to map group codes to labels
#   lonely_psu_option - How to handle lonely PSUs (default: "adjust")
#
# Outputs:
#   Data frame with rate, SE, 95% CI, and optional group labels
# ------------------------------------------------------------------

analyze_survey_var <- function(var_name, design, 
                               na_codes = c(9, NA), 
                               group = NULL, 
                               label_map = NULL) {
  

  # Create cleaned temporary variable in the design
  design$variables$tmp_var <- ifelse(design$variables[[var_name]] %in% na_codes, NA, design$variables[[var_name]])
  
  if (is.null(group)) {
    # Overall estimate
    est <- svymean(~tmp_var, design = design, na.rm = TRUE)
    est_df <- data.frame(
      rate = coef(est),
      se = SE(est),
      lower_ci = coef(est) - 1.96 * SE(est),
      upper_ci = coef(est) + 1.96 * SE(est)
    )
  } else {
    # Grouped estimate
    by_formula <- as.formula("~tmp_var")
    group_formula <- as.formula(paste("~", group))
    est <- svyby(by_formula, group_formula, design, FUN = svymean, na.rm = TRUE)
    
    # Grab first mean and SE columns
    est_df <- est %>%
      mutate(
        rate = est[[2]],
        se = est[[3]],
        lower_ci = rate - 1.96 * se,
        upper_ci = rate + 1.96 * se
      )
    
    # Apply label mapping if provided
    if (!is.null(label_map)) est_df[[group]] <- label_map[as.character(est_df[[group]])]
  }
  
  est_df
}