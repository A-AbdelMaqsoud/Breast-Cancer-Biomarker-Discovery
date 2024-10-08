# Load required libraries
if (!requireNamespace("BiocManager", quietly = TRUE))
  install.packages("BiocManager")

BiocManager::install("TCGAbiolinks")
BiocManager::install("DESeq2")
BiocManager::install("biomaRt")
BiocManager::install("ggplot2")

library(TCGAbiolinks)
library(DESeq2)
library(dplyr)
library(biomaRt)
library(ggplot2)

# Query and download BRCA data from TCGA
query_TCGA <- GDCquery(project = 'TCGA-BRCA',
                       data.category = 'Transcriptome Profiling',
                       data.type = 'Gene Expression Quantification',
                       experimental.strategy = 'RNA-Seq',
                       workflow.type = 'STAR - Counts',
                       access = 'open')

GDCdownload(query_TCGA)
expression_data <- GDCprepare(query_TCGA)

# Convert data to DataFrame
data <- assay(expression_data)
data <- as.data.frame(data)

# Check for missing values
sum(is.na(data))

# Handle missing values: Filter genes with a high proportion of missing values
threshold <- 0.2 # Remove genes if more than 20% of values are missing
data <- data[rowSums(is.na(data)) < threshold * ncol(data), ]

# Handle remaining missing values: Replace remaining NAs with 0
data[is.na(data)] <- 0

# Use DESeq2 for transformation using Variance Stabilizing Transformation (VST)
dds <- DESeqDataSetFromMatrix(countData = data,
                              colData = colData(expression_data),
                              design = ~ sample_type)

# Apply the transformation
vsd <- vst(dds, blind = TRUE)
normalized_data <- assay(vsd) # Extract transformed data

# Reduce the dataset to 20 primary tumor samples and 20 recurrent tumor samples
if("sample_type" %in% colnames(colData(expression_data))) {
  sample_info <- as.data.frame(colData(expression_data)) # Extract additional information (Metadata)
  
  # Select primary and recurrent samples
  primary_samples <- sample_info %>% filter(sample_type == "Primary Tumor") %>% head(20)
  recurrent_samples <- sample_info %>% filter(sample_type == "Recurrent Tumor") %>% head(20)
  
  # Combine selected samples
  selected_samples <- rbind(primary_samples, recurrent_samples)
  
  # Filter expression data based on selected samples
  reduced_data <- normalized_data[, rownames(selected_samples)]
} else {
  stop("Column 'sample_type' not found in metadata.")
}

# Check dimensions of the reduced data
dim(reduced_data)

# Add the 'group' variable to the design matrix in DESeq2
selected_sample_names <- rownames(selected_samples)
sample_type_factor <- factor(c(rep("Primary", 20), rep("Recurrent", 20)))

dds_subset <- DESeqDataSetFromMatrix(countData = data[, selected_sample_names],
                                     colData = data.frame(row.names = selected_sample_names, sample_type = sample_type_factor),
                                     design = ~ sample_type)

# Perform differential gene expression analysis
dds_subset <- DESeq(dds_subset)
res <- results(dds_subset)

# Sort results by p-value and adjust using the Benjamini-Hochberg method
res_ordered <- res[order(res$padj), ]

# Extract results for genes with significant differential expression
significant_genes <- subset(res_ordered, padj < 0.05)

# Display the final results
head(significant_genes)

# Display the number of genes with significant differential expression
cat("Number of significant genes:", nrow(significant_genes), "\n")

# Create a Volcano plot to visualize genes with significant differential expression
res_ordered$significant <- ifelse(res_ordered$padj < 0.05, "Significant", "Not Significant")

volcano_plot <- ggplot(res_ordered, aes(x = log2FoldChange, y = -log10(padj))) +
  geom_point(aes(color = significant), alpha = 0.8) +
  scale_color_manual(values = c("Significant" = "red", "Not Significant" = "gray")) +
  theme_minimal() +
  labs(title = "Volcano Plot of Differential Gene Expression",
       x = "Log2 Fold Change",
       y = "-log10 Adjusted P-value") +
  theme(legend.position = "bottom")

print(volcano_plot)

# Save the Volcano plot
ggsave("volcano_plot.png", volcano_plot, width = 10, height = 8)

# Create an MA plot
png("ma_plot.png", width = 800, height = 600)
plotMA(res, main = "MA Plot", ylim = c(-5, 5))
dev.off()

# Display the top 10 most significantly differentially expressed genes
top_10_genes <- head(significant_genes, 10)
print(top_10_genes)

# Save the results to a CSV file
write.csv(significant_genes, "significant_genes.csv", row.names = TRUE)

# Print a summary of the analysis
cat("\nAnalysis Summary:\n")
cat("Total number of genes analyzed:", nrow(res), "\n")
cat("Number of significantly differentially expressed genes:", nrow(significant_genes), "\n")
cat("Top 10 most significant genes:\n")
print(rownames(top_10_genes))

# Final message
cat("\nAnalysis complete. Results and visualizations have been saved.\n")
