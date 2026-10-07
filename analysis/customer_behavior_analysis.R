# Customer behaviour analysis
#
# Cleaned version of the R workflow used for the university project.
# The analysis and hypothesis tests are kept close to the submitted version.
# Source data are restricted and are not included in the public repository.

library(dplyr)
library(ggplot2)
library(RColorBrewer)
library(caret)
library(mice)

DATA_FILE <- file.path("data", "private", "last_fixed_table.csv")
WEATHER_FILE <- file.path("data", "private", "WeatherTable.txt")
GENDER_LOOKUP_FILE <- file.path("data", "private", "gender_lookup.csv")

wehkamp <- read.csv(DATA_FILE)

str(wehkamp)
summary(wehkamp)

# Replace text NULL values with NA
wehkamp[] <- lapply(wehkamp, function(col) {
  if (is.factor(col)) {
    col <- as.character(col)
  }

  if (is.character(col)) {
    col[col == "NULL"] <- NA
  }

  if (suppressWarnings(all(is.na(col) | !is.na(as.numeric(col))))) {
    numeric_col <- suppressWarnings(as.numeric(col))
    if (!all(is.na(numeric_col))) {
      col <- numeric_col
    }
  }

  col
})

wehkamp <- as.data.frame(wehkamp)

# Set the variables used later in the analysis
wehkamp$session_duration <- as.numeric(wehkamp$session_duration)
wehkamp$device_used <- as.factor(wehkamp$device_used)
wehkamp$conversion <- as.numeric(wehkamp$conversion)
wehkamp$session_date <- as.Date(wehkamp$session_date)
wehkamp$geom_urbanisation <- as.factor(wehkamp$geom_urbanisation)
wehkamp$action_type_desc <- as.factor(wehkamp$action_type_desc)
wehkamp$geom_household_age <- as.factor(wehkamp$geom_household_age)
wehkamp$geom_household_income <- as.factor(wehkamp$geom_household_income)

# The original source stored gender as hashed values. The lookup stays private.
# gender_lookup.csv needs two columns: gender_code_raw and gender_label.
gender_lookup <- read.csv(GENDER_LOOKUP_FILE, stringsAsFactors = FALSE)

wehkamp <- wehkamp %>%
  mutate(gender_code = as.character(gender_code)) %>%
  left_join(gender_lookup, by = c("gender_code" = "gender_code_raw")) %>%
  mutate(gender_code = ifelse(!is.na(gender_label), gender_label, gender_code)) %>%
  select(-gender_label)

wehkamp$gender_code <- as.factor(wehkamp$gender_code)

summary(wehkamp)

# Missing-value preparation
imputed <- wehkamp[, c(
  "session_duration",
  "device_used",
  "gender_code",
  "geom_household_income",
  "geom_household_age",
  "geom_urbanisation"
)]

imputed$session_duration <- as.numeric(imputed$session_duration)
imputed$geom_urbanisation <- as.numeric(as.character(imputed$geom_urbanisation))

age_levels <- c(
  "0. Unknown", "1. < 25 years", "2. 25 - 29 years",
  "3. 30 - 34 years", "4. 35 - 39 years", "5. 40 - 44 years",
  "6. 45 - 49 years", "7. 50 - 54 years", "8. 55 - 59 years",
  "9. 60 - 64 years", "10. 65 - 69 years", "11. 70 - 74 years",
  "12. 75 - 79 years", "13. >= 80 years"
)

income_levels <- c(
  "0. Unknown", "1. < 18,000", "2. 18,000 - 26,000",
  "3. 26,000 - 35,000", "4. 35,000 - 50,000",
  "5. 50,000 - 75,000", "6. 75,000 - 100,000",
  "7. 100,000 - 200,000", "8. >= 200,000"
)

imputed$geom_household_age <- as.numeric(
  factor(imputed$geom_household_age, levels = age_levels, labels = 0:13)
)

imputed$geom_household_income <- as.numeric(
  factor(imputed$geom_household_income, levels = income_levels, labels = 0:8)
)

imputed$device_used <- as.numeric(
  factor(imputed$device_used,
         levels = c("mobile", "desktop", "tablet"),
         labels = c(1, 2, 3))
)

imputed$gender_code <- as.numeric(
  factor(imputed$gender_code,
         levels = c("female", "male", "others"),
         labels = c(1, 2, 3))
)

md.pattern(imputed)

PredictorMatrix <- matrix(c(
  0, 1, 1, 1, 1, 1,
  1, 0, 1, 1, 1, 1,
  1, 1, 0, 1, 1, 1,
  1, 1, 1, 0, 1, 1,
  1, 1, 1, 1, 0, 1,
  1, 1, 1, 1, 1, 0
), nrow = 6, ncol = 6, byrow = TRUE)

rownames(PredictorMatrix) <- colnames(PredictorMatrix) <- c(
  "session_duration",
  "device_used",
  "gender_code",
  "geom_household_income",
  "geom_household_age",
  "geom_urbanisation"
)

print(PredictorMatrix)

# Keep the submitted imputation setup: five imputations, 50 iterations and PMM.
MiceImputedData <- mice(
  imputed,
  m = 5,
  maxit = 50,
  method = "pmm",
  predictorMatrix = PredictorMatrix,
  seed = 500
)

summary(MiceImputedData)

# These checks were part of the original workflow.
MiceAllModels_session <- with(
  data = MiceImputedData,
  lm(session_duration ~ device_used + gender_code + geom_household_income + geom_household_age + geom_urbanisation)
)
MiceAllModels_device <- with(
  data = MiceImputedData,
  lm(device_used ~ session_duration + gender_code + geom_household_income + geom_household_age + geom_urbanisation)
)
MiceAllModels_gender <- with(
  data = MiceImputedData,
  lm(gender_code ~ session_duration + device_used + geom_household_income + geom_household_age + geom_urbanisation)
)
MiceAllModels_income <- with(
  data = MiceImputedData,
  lm(geom_household_income ~ session_duration + device_used + gender_code + geom_household_age + geom_urbanisation)
)
MiceAllModels_age <- with(
  data = MiceImputedData,
  lm(geom_household_age ~ session_duration + device_used + gender_code + geom_household_income + geom_urbanisation)
)
MiceAllModels_urbanisation <- with(
  data = MiceImputedData,
  lm(geom_urbanisation ~ session_duration + device_used + gender_code + geom_household_income + geom_household_age)
)

summary(pool(MiceAllModels_session))
summary(pool(MiceAllModels_device))
summary(pool(MiceAllModels_gender))
summary(pool(MiceAllModels_income))
summary(pool(MiceAllModels_age))
summary(pool(MiceAllModels_urbanisation))

imputed_final <- complete(MiceImputedData, 1)

# Put the imputed values back into the main table
wehkamp$session_duration[is.na(wehkamp$session_duration)] <-
  imputed_final$session_duration[is.na(wehkamp$session_duration)]

wehkamp$device_used <- factor(
  imputed_final$device_used,
  levels = c(1, 2, 3),
  labels = c("mobile", "desktop", "tablet")
)

wehkamp$gender_code <- factor(
  imputed_final$gender_code,
  levels = c(1, 2, 3),
  labels = c("female", "male", "others")
)

wehkamp$geom_household_income <- factor(
  imputed_final$geom_household_income,
  levels = 0:8,
  labels = income_levels
)

wehkamp$geom_household_age <- factor(
  imputed_final$geom_household_age,
  levels = 0:13,
  labels = age_levels
)

wehkamp$geom_urbanisation <- factor(
  round(imputed_final$geom_urbanisation),
  levels = c(1, 2, 3, 4, 5),
  labels = c("1. High urbanisation", "2", "3", "4", "5. Low urbanisation")
)

colSums(is.na(wehkamp))
summary(wehkamp)

# Weather data
weather <- read.csv(WEATHER_FILE)
weather <- weather[, -1]

weather$TG <- weather$TG / 10
weather$SQ <- weather$SQ / 10
weather$DR <- weather$DR / 10

colnames(weather)[colnames(weather) == "YYYYMMDD"] <- "date"
colnames(weather)[colnames(weather) == "SQ"] <- "sunshine_hours"
colnames(weather)[colnames(weather) == "TG"] <- "temperature"
colnames(weather)[colnames(weather) == "DR"] <- "rain_hours"

weather$date <- as.Date(as.character(weather$date), format = "%Y%m%d")

str(weather)
summary(weather)

# Join weather to the browsing data by date
dataset <- left_join(wehkamp, weather, by = c("session_date" = "date"))

dataset$season <- factor(
  dataset$season,
  levels = c(1, 2, 3, 4),
  labels = c("Spring", "Summer", "Autumn", "Winter")
)

# These session-level variables are needed in several later sections.
dataset <- dataset %>%
  group_by(internet_session_id) %>%
  mutate(
    has_add_to_cart = any(action_type_desc == "add to cart", na.rm = TRUE),
    has_purchase = any(action_type_desc == "purchase", na.rm = TRUE),
    cart_abandonment = ifelse(has_add_to_cart & !has_purchase, 1, 0),
    product_page_visits = sum(action_type_desc == "product detail view")
  ) %>%
  ungroup()

# This spelling is kept from the submitted analysis because it reproduces
# the original H1/H10 outputs. See ANALYSIS_NOTES.md before changing it.
dataset <- dataset %>%
  mutate(age_group = ifelse(
    geom_household_age %in% c("1. < 25 years", "2. 25-30 years"),
    "<30",
    "30+"
  ))

# Outlier checks
outlier_data <- dataset %>%
  mutate(
    age_group = as.factor(age_group),
    season = as.factor(season)
  )

encoded <- model.matrix(
  ~ session_duration + conversion + temperature + age_group + season,
  data = outlier_data
)[, -1]

encoded <- encoded[, apply(encoded, 2, var) > 0]
cor_matrix <- cor(encoded)
findCorrelation(cor_matrix, cutoff = 0.9)

Sx <- cov(encoded)
D2 <- mahalanobis(encoded, colMeans(encoded), Sx)

plot(
  density(D2, bw = 0.5),
  main = "Squared Mahalanobis distances",
  lwd = 2
)
rug(D2)

xrange <- seq(0, 12, by = 0.001)
lines(xrange, dchisq(xrange, 5), col = "dodgerblue", lwd = 2)

qqplot(
  qchisq(ppoints(100), df = 5),
  D2,
  main = expression("Q-Q plot of Mahalanobis" * ~D^2 *
                      " vs. quantiles of" * ~chi[5]^2)
)
abline(0, 1, col = "gray")

detect_outliers <- function(x) {
  Q1 <- quantile(x, 0.25, na.rm = TRUE)
  Q3 <- quantile(x, 0.75, na.rm = TRUE)
  IQR_value <- Q3 - Q1
  lower_bound <- Q1 - 1.5 * IQR_value
  upper_bound <- Q3 + 1.5 * IQR_value
  x[x < lower_bound | x > upper_bound]
}

print(detect_outliers(weather$temperature))
print(detect_outliers(weather$sunshine_hours))
print(detect_outliers(weather$rain_hours))

# Descriptive checks
summary(dataset)
table(dataset$device_used)
table(dataset$geom_household_age)
table(dataset$geom_household_income)
table(dataset$season)

daily_purchases <- dataset %>%
  group_by(session_date) %>%
  summarise(total_purchases = sum(has_purchase), .groups = "drop")

ggplot(daily_purchases, aes(x = session_date, y = total_purchases)) +
  geom_line(color = "dodgerblue2", linewidth = 0.5) +
  labs(
    title = "Daily Purchases Over Time",
    x = "Date",
    y = "Total Purchases"
  ) +
  theme_minimal()

ggplot(dataset, aes(x = device_used, fill = factor(conversion))) +
  geom_bar(position = "fill") +
  labs(
    title = "Conversion Rate by Device Type",
    x = "Device Type",
    y = "Proportion of Conversions"
  ) +
  scale_fill_manual(
    values = RColorBrewer::brewer.pal(2, "Set2"),
    labels = c("No Conversion", "Conversion")
  ) +
  scale_y_continuous(labels = scales::percent)

# H1: Younger shoppers (<30) have a higher cart abandonment rate
cart_abandonment_by_age <- dataset %>%
  group_by(age_group) %>%
  summarise(cart_abandonment_rate = mean(cart_abandonment), .groups = "drop")

print(cart_abandonment_by_age)

abandonment_table <- table(dataset$age_group, dataset$cart_abandonment)
chisq_h1 <- chisq.test(abandonment_table)
print(chisq_h1)

logit_h1 <- glm(
  cart_abandonment ~ age_group,
  data = dataset,
  family = "binomial"
)
summary(logit_h1)

# H4: Longer sessions are associated with purchase
session_duration_by_purchase <- dataset %>%
  group_by(has_purchase) %>%
  summarise(avg_session_duration = mean(session_duration, na.rm = TRUE), .groups = "drop")

print(session_duration_by_purchase)

t_test_h4 <- t.test(session_duration ~ has_purchase, data = dataset)
print(t_test_h4)

logit_h4 <- glm(
  has_purchase ~ session_duration,
  data = dataset,
  family = "binomial"
)
summary(logit_h4)

# H5: Men have shorter sessions than women
dataset_filtered <- dataset %>%
  filter(gender_code %in% c("male", "female"))

session_duration_by_gender <- dataset_filtered %>%
  group_by(gender_code) %>%
  summarise(avg_session_duration = mean(session_duration, na.rm = TRUE), .groups = "drop")

print(session_duration_by_gender)

t_test_h5 <- t.test(session_duration ~ gender_code, data = dataset_filtered)
print(t_test_h5)

lm_h5 <- lm(session_duration ~ gender_code, data = dataset_filtered)
summary(lm_h5)

# H6: Repeated product-page visits within a short session are associated with purchase
dataset <- dataset %>%
  mutate(short_window_visits = ifelse(
    product_page_visits > 1 & session_duration <= 180,
    1,
    0
  ))

purchase_by_visit_pattern <- dataset %>%
  group_by(short_window_visits) %>%
  summarise(purchase_rate = mean(has_purchase), .groups = "drop")

print(purchase_by_visit_pattern)

visit_table <- table(dataset$short_window_visits, dataset$has_purchase)
chisq_h6 <- chisq.test(visit_table)
print(chisq_h6)

logit_h6 <- glm(
  has_purchase ~ short_window_visits,
  data = dataset,
  family = "binomial"
)
summary(logit_h6)

ggplot(
  purchase_by_visit_pattern,
  aes(x = as.factor(short_window_visits), y = purchase_rate, fill = as.factor(short_window_visits))
) +
  geom_bar(stat = "identity") +
  labs(
    title = "Purchase Rate by Short Window Visit Behavior",
    x = "Multiple Visits Within Short Time (0 = No, 1 = Yes)",
    y = "Purchase Rate"
  ) +
  theme_minimal()

# H7: Desktop users have a higher conversion rate than mobile and tablet users
conversion_by_device <- dataset %>%
  group_by(device_used) %>%
  summarise(conversion_rate = mean(conversion, na.rm = TRUE), .groups = "drop")

print(conversion_by_device)

conversion_table <- table(dataset$device_used, dataset$conversion)
chisq_h7 <- chisq.test(conversion_table)
print(chisq_h7)

logit_h7 <- glm(conversion ~ device_used, data = dataset, family = "binomial")
summary(logit_h7)

ggplot(conversion_by_device, aes(x = device_used, y = conversion_rate, fill = device_used)) +
  geom_bar(stat = "identity") +
  labs(
    title = "Conversion Rate by Device Type",
    x = "Device Type",
    y = "Conversion Rate"
  ) +
  theme_minimal()

# H8: Sunny weather is associated with a higher conversion rate
dataset <- dataset %>%
  mutate(weather_condition = ifelse(
    sunshine_hours > rain_hours,
    "Sunny",
    "Rainy"
  ))

conversion_by_weather <- dataset %>%
  group_by(weather_condition) %>%
  summarise(conversion_rate = mean(conversion, na.rm = TRUE), .groups = "drop")

print(conversion_by_weather)

weather_table <- table(dataset$weather_condition, dataset$conversion)
chisq_h8 <- chisq.test(weather_table)
print(chisq_h8)

logit_h8 <- glm(
  conversion ~ weather_condition,
  data = dataset,
  family = "binomial"
)
summary(logit_h8)

ggplot(
  conversion_by_weather,
  aes(x = weather_condition, y = conversion_rate, fill = weather_condition)
) +
  geom_bar(stat = "identity") +
  labs(
    title = "Conversion Rate by Weather Condition",
    x = "Weather Condition",
    y = "Conversion Rate"
  ) +
  theme_minimal()

# H9: Conversion varies by season
conversion_by_season <- dataset %>%
  group_by(season) %>%
  summarise(conversion_rate = mean(conversion, na.rm = TRUE), .groups = "drop")

print(conversion_by_season)

season_table <- table(dataset$season, dataset$conversion)
chisq_h9 <- chisq.test(season_table)
print(chisq_h9)

logit_h9 <- glm(
  conversion ~ factor(season),
  data = dataset,
  family = "binomial"
)
summary(logit_h9)

ggplot(
  conversion_by_season,
  aes(x = factor(season), y = conversion_rate, fill = factor(season))
) +
  geom_bar(stat = "identity") +
  scale_fill_brewer(palette = "Set1") +
  labs(
    title = "Conversion Rate by Season",
    x = "Season",
    y = "Conversion Rate"
  ) +
  theme_minimal()

# H10: Test whether the temperature relationship differs by age group
dataset <- dataset %>%
  mutate(temp_category = case_when(
    temperature < 10 ~ "Cold",
    temperature >= 10 & temperature < 20 ~ "Mild",
    temperature >= 20 ~ "Hot"
  ))

conversion_by_temp_age <- dataset %>%
  group_by(temp_category, age_group) %>%
  summarise(conversion_rate = mean(conversion, na.rm = TRUE), .groups = "drop")

print(conversion_by_temp_age)

logit_h10 <- glm(conversion ~ temperature, data = dataset, family = "binomial")
summary(logit_h10)

dataset$age_group <- relevel(factor(dataset$age_group), ref = "<30")

logit_h10_age <- glm(
  conversion ~ temperature + age_group + temperature * age_group,
  data = dataset,
  family = "binomial"
)
summary(logit_h10_age)
exp(coef(logit_h10_age))

# H11: Urbanisation is associated with conversion
conversion_by_urban <- dataset %>%
  group_by(geom_urbanisation) %>%
  summarise(conversion_rate = mean(conversion, na.rm = TRUE), .groups = "drop")

print(conversion_by_urban)

urban_table <- table(dataset$geom_urbanisation, dataset$conversion)
chisq_h11 <- chisq.test(urban_table)
print(chisq_h11)

logit_h11 <- glm(
  conversion ~ geom_urbanisation + session_duration + temperature + season,
  data = dataset,
  family = "binomial"
)
summary(logit_h11)
exp(coef(logit_h11))

ggplot(
  conversion_by_urban,
  aes(x = as.factor(geom_urbanisation), y = conversion_rate, fill = as.factor(geom_urbanisation))
) +
  geom_bar(stat = "identity") +
  scale_fill_brewer(palette = "Set1") +
  labs(
    title = "Conversion Rate by Urbanization Level",
    x = "Urbanization Level",
    y = "Conversion Rate"
  ) +
  theme_minimal()

# H12: Test whether household income moderates the urbanisation relationship
h12_data <- dataset %>%
  mutate(
    geom_urbanisation_num = as.numeric(geom_urbanisation),
    geom_household_income_num = as.numeric(geom_household_income),
    urban_income_interaction = geom_urbanisation_num * geom_household_income_num
  )

logit_h12 <- glm(
  conversion ~ geom_urbanisation_num + geom_household_income_num + urban_income_interaction,
  data = h12_data,
  family = "binomial"
)
summary(logit_h12)
