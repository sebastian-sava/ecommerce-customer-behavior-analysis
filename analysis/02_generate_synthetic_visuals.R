# Synthetic portfolio visuals
#
# These charts use synthetic values only. They show the types of comparisons
# made in the original project without publishing restricted retail results.

library(ggplot2)
library(scales)

visual_values <- read.csv("data/synthetic_visual_values.csv", stringsAsFactors = FALSE)

save_bar <- function(data, title, x_label, y_label, filename) {
  p <- ggplot(data, aes(x = category, y = rate)) +
    geom_col() +
    geom_text(aes(label = percent(rate, accuracy = 0.1)), vjust = -0.4) +
    scale_y_continuous(labels = percent, limits = c(0, max(data$rate) * 1.2)) +
    labs(
      title = title,
      subtitle = "Synthetic portfolio illustration — not original restricted project results",
      x = x_label,
      y = y_label
    ) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none")

  svg(file.path("visuals", filename), width = 8, height = 5)
  print(p)
  dev.off()
}

device <- subset(visual_values, chart == "conversion_by_device")
season <- subset(visual_values, chart == "conversion_by_season")
visits <- subset(visual_values, chart == "purchase_rate_by_short_window_visits")

save_bar(
  device,
  "Conversion Rate by Device Type",
  "Device type",
  "Conversion rate",
  "conversion_by_device.svg"
)

save_bar(
  season,
  "Conversion Rate by Season",
  "Season",
  "Conversion rate",
  "conversion_by_season.svg"
)

save_bar(
  visits,
  "Purchase Rate by Short-Window Revisit Behaviour",
  "Visit pattern",
  "Purchase rate",
  "purchase_rate_by_short_window_visits.svg"
)
