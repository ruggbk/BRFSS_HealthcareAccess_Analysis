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