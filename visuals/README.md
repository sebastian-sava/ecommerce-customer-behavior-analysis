# Visuals

I would keep the public README visually simple.

## Include now

The Mermaid workflow diagram in the main README is safe to publish because it shows the analysis process rather than restricted company results.

## Add once a synthetic dataset is available

These are the three result visuals I would prioritise:

1. **Conversion rate by device type**  
   A simple bar chart. This is easy to read and directly connects browsing behaviour to a practical UX question.

2. **Conversion rate by season**  
   Useful for separating traffic volume from conversion efficiency and showing the role of seasonality.

3. **Purchase rate by short-window revisit behaviour**  
   Shows how a behavioural feature was constructed and tested, and is more interesting than a generic demographic chart.

An optional fourth visual is a **daily purchases over time** line chart to show the seasonal shape before moving into the statistical tests.

## Do not lead with

- Mahalanobis-distance plots;
- raw regression coefficient tables;
- the full set of hypothesis charts;
- screenshots from the original university report.

Those can be useful during technical discussion, but they make the GitHub landing page feel more academic and less focused.

The original report charts and exact company-specific results should not be copied into the public repository. When synthetic data is created, the R script can regenerate portfolio-safe versions of the selected charts.
