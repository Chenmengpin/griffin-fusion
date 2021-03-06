# ==============================================================================
# Multiple samples
# Steven Foltz (github: envest)
# ==============================================================================

paper_main = "paper/main/03_multiple/"
paper_supp = "paper/supplementary/03_multiple/"

# Create directories
dir.create(paper_main, recursive = TRUE, showWarnings = FALSE)
dir.create(paper_supp, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# Explore the landscape of fusions in samples with multiple timepoints
# Originally written September 2018, Updated April 2019
# ==============================================================================

if (TRUE) {

  # Fusions involving important genes

  fusions_with_important_genes <- fusions_all %>%
    filter( str_detect(fusion, "WHSC1") |
              str_detect(fusion, "FGFR3") |
              str_detect(fusion, "MYC") |
              str_detect(fusion, "PVT1") |
              !(geneA %in% c("IGH", "IGK", "IGL") |
                  geneB %in% c("IGH", "IGK", "IGL"))) %>%
    filter( geneA_oncogene | geneA_tsg | geneA_kinase |
              geneA_mmy_known | geneA_driver |
              geneB_oncogene | geneB_tsg | geneB_kinase |
              geneB_mmy_known | geneB_driver |
              drug_fusion | drug_geneA | drug_geneB) %>%
    select(mmrf, fusion) %>% unique() %>% group_by(fusion) %>%
    summarize(n()) %>%
    pull(fusion)

  # samples with multiple bone marrow samples
  mtp_bm_samples <- samples_all %>%
    filter(tissue_source == "BM") %>%
    group_by(mmrf) %>%
    summarize(n_bm_samples = n(),
              bm_visits = str_c(c(visit), collapse = ":"),
              bm_srr = str_c(c(srr), collapse = ":")) %>%
    filter(n_bm_samples > 1) %>%
    group_by(mmrf) %>%
    mutate(first_srr = str_split(bm_srr, ":", simplify = TRUE)[1],
           second_srr = str_split(bm_srr, ":", simplify = TRUE)[2]) %>%
    ungroup() %>%
    select(mmrf, first_srr, second_srr)

  # samples with same time points BMs and PBs
  stp_bmpb_samples <- samples_all %>%
    group_by(mmrf, visit) %>%
    summarize(n_samples = n(),
              tissue_sources = str_c(c(tissue_source), collapse = ":"),
              source_srr = str_c(c(srr), collapse = ":")) %>%
    filter(n_samples > 1,
           str_detect(tissue_sources, "BM"),
           str_detect(tissue_sources, "PB")) %>%
    group_by(mmrf, visit) %>%
    mutate(first_srr = str_split(source_srr, ":", simplify = TRUE)[1],
           second_srr = str_split(source_srr, ":", simplify = TRUE)[2]) %>%
    ungroup() %>%
    select(mmrf, first_srr, second_srr)

  # method to overlap fusion calls from two SRRs
  get_fusion_overlap <- function(fusion_df, srr1, srr2){
    list_of_fusions_srr1 <- fusion_df %>%
      filter(srr == srr1) %>%
      pull(fusion) %>%
      sort()
    list_of_fusions_srr2 <- fusion_df %>%
      filter(srr == srr2) %>%
      pull(fusion) %>%
      sort()
    if ("IGH--WHSC1" %in% list_of_fusions_srr1 |
        "WHSC1--IGH" %in% list_of_fusions_srr1) {
      srr1_has_founder <- 1
    } else {
      srr1_has_founder <- 0
    }
    if ("IGH--WHSC1" %in% list_of_fusions_srr2 |
        "WHSC1--IGH" %in% list_of_fusions_srr2) {
      srr2_has_founder <- 1
    } else {
      srr2_has_founder <- 0
    }
    founder_status = 1*srr1_has_founder + 2*srr2_has_founder
    n_srr1 <- length(list_of_fusions_srr1)
    n_srr2 <- length(list_of_fusions_srr2)
    overlap_srr12 <- intersect(list_of_fusions_srr1,
                               list_of_fusions_srr2) %>% length()
    return(str_c(n_srr1, n_srr2, overlap_srr12, founder_status, sep = ":"))
  }

  p_df <- mtp_bm_samples %>%
    rowwise() %>%
    mutate(overlaps = get_fusion_overlap(fusions_all, first_srr, second_srr)) %>%
    separate(overlaps,
             into = c("n_fusions_srr1", "n_fusions_srr2",
                      "overlap_srr12", "ighwhsc1"), sep = ":") %>%
    mutate(n_fusions_srr1 = as.integer(n_fusions_srr1),
           n_fusions_srr2 = as.integer(n_fusions_srr2),
           overlap_srr12 = as.integer(overlap_srr12),
           igh_whsc1 = case_when(ighwhsc1 == "0" ~ "Neither sample",
                                 ighwhsc1 == "1" ~ "TP1 only",
                                 ighwhsc1 == "2" ~ "TP2 only",
                                 ighwhsc1 == "3" ~ "Both samples")) %>%
    rowwise() %>%
    mutate(min_srr12 = min(n_fusions_srr1, n_fusions_srr2)) %>%
    ungroup() %>%
    mutate(igh_whsc1 = factor(igh_whsc1,
                              levels = c("Both samples", "Neither sample",
                                         "TP1 only", "TP2 only"), ordered = TRUE))

  p_df_min_max <- p_df %>% pull(min_srr12) %>% max()

  n_patients_two_bm <- p_df %>% pull(mmrf) %>% unique() %>% length()
  table_two_bm_ighwhsc1 <- p_df %>% pull(igh_whsc1) %>% table()
  info_tp1_ighwhsc1_falsenegative <- p_df %>% filter(igh_whsc1 == "TP2 only") %>%
    select(mmrf) %>% left_join(expression_primary, by = "mmrf") %>%
    filter(gene == "WHSC1") %>% select(mmrf, srr, gene, pct)

  cor_tp1tp2_n_fusions <- cor.test(p_df %>% pull(n_fusions_srr1), p_df %>% pull(n_fusions_srr2))

  p <- ggplot(data = p_df, aes(x = n_fusions_srr1, y = n_fusions_srr2)) +
    geom_abline(linetype = 2, color = "grey50") +
    geom_smooth(method = "lm") +
    geom_point(aes(size = overlap_srr12, color = igh_whsc1), shape = 16) +
    geom_point(aes(color = igh_whsc1), shape = 3, size = 2) +
    scale_color_brewer(palette = "Set2", drop = FALSE, direction = -1) +
    scale_size_area(breaks = c(0, 2, 4, 6, 8, 10)) +
    labs(x = "Number of Fusions (Time Point 1)",
         y = "Number of Fusions (Time Point 2)",
         size = "Number of\nOverlapping\nFusion Calls",
         color = "IGH--WHSC1\nDetected") +
    theme_bw() +
    theme(plot.background = element_blank(),
          panel.background = element_blank(),
          panel.border = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text = element_text(size = 8),
          axis.ticks = element_blank(),
          axis.title = element_text(size = 10),
          legend.background = element_blank(),
          legend.text = element_text(size = 10))

  p_min_overlap <- ggplot(data = p_df, aes(x = min_srr12, y = overlap_srr12)) +
    geom_abline(linetype = 2, color = "grey50") +
    geom_smooth(method = "lm") +
    geom_point(aes(color = igh_whsc1), shape = 16) +
    geom_point(aes(color = igh_whsc1), shape = 3, size = 2) +
    scale_color_brewer(palette = "Set2", drop = FALSE, direction = -1) +
    scale_size_area(breaks = c(0, 2, 4, 6, 8, 10)) +
    labs(x = "Minimum Fusions (Time Point 1 or 2)",
         y = "Overlapping Fusions (Time Point 1 and 2)",
         size = "Number of\nOverlapping\nFusion Calls",
         color = "IGH--WHSC1\nDetected") +
    theme_bw() +
    xlim(0, p_df_min_max) + ylim(0, p_df_min_max) +
    theme(plot.background = element_blank(),
          panel.background = element_blank(),
          panel.border = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text = element_text(size = 8),
          axis.ticks = element_blank(),
          axis.title = element_text(size = 10),
          legend.background = element_blank(),
          legend.text = element_text(size = 10))

  ggsave(str_c(paper_main, "multiple_timepoints.bm.pdf"),
         p,
         device = "pdf", width = 2.75, height = 7.5, useDingbats = FALSE)
  ggsave(str_c(paper_main, "multiple_timepoints.bm.no_legend.pdf"),
         p + guides(size = FALSE, color = FALSE),
         device = "pdf", width = 2.75, height = 2.75, useDingbats = FALSE)
  ggsave(str_c(paper_supp, "multiple_timepoints.bm.min_overlap.pdf"),
         p_min_overlap,
         device = "pdf", width = 2.75, height = 7.5, useDingbats = FALSE)
  ggsave(str_c(paper_supp, "multiple_timepoints.bm.min_overlap.no_legend.pdf"),
         p_min_overlap + guides(size = FALSE, color = FALSE),
         device = "pdf", width = 2.75, height = 2.75, useDingbats = FALSE)

  # Function to define background normalized Hamming distance
  # Conservatively define success probability as the frequency of IGH--WHSC1 fusion
  # vector_length is max + min - overlap
  # n_tests can be 1000 or whatever you want
  background_normalized_hamming_distance <- function(vector_length, success_probability, n_tests){
    nhd_vector <- sapply(rep(vector_length, n_tests),
                         function(x) mean((rbernoulli(x, success_probability) + rbernoulli(x, success_probability) + 1) %% 2))
    return(nhd_vector)
  }

  most_common_fusion_rate <- fusions_primary %>%
    group_by(fusion) %>%
    tally() %>%
    filter(n == max(n)) %>%
    pull(n)/nrow(fusions_primary)

  q_df <- stp_bmpb_samples %>%
    rowwise() %>%
    mutate(overlaps = get_fusion_overlap(fusions_all, first_srr, second_srr)) %>%
    separate(overlaps, into = c("n_fusions_srr1", "n_fusions_srr2", "overlap_srr12", "ighwhsc1"), sep = ":") %>%
    mutate(n_fusions_srr1 = as.integer(n_fusions_srr1),
           n_fusions_srr2 = as.integer(n_fusions_srr2),
           overlap_srr12 = as.integer(overlap_srr12),
           igh_whsc1 = case_when(ighwhsc1 == "0" ~ "Neither sample",
                                 ighwhsc1 == "1" ~ "TP1 only",
                                 ighwhsc1 == "2" ~ "TP2 only",
                                 ighwhsc1 == "3" ~ "Both samples")) %>%
    rowwise() %>%
    mutate(min_srr12 = min(n_fusions_srr1, n_fusions_srr2)) %>%
    mutate(max_srr12 = max(n_fusions_srr1, n_fusions_srr2)) %>%
    ungroup() %>%
    mutate(igh_whsc1 = factor(igh_whsc1, levels = c("Both samples", "Neither sample", "TP1 only", "TP2 only"), ordered = TRUE)) %>%
    mutate(normalized_hamming_distance = (max_srr12 + min_srr12 - 2*overlap_srr12)/(max_srr12 + min_srr12 - overlap_srr12)) %>%
    rowwise() %>%
    mutate(hamming_p_value = mean(background_normalized_hamming_distance(max_srr12 + min_srr12 - overlap_srr12, most_common_fusion_rate, 10000) <= normalized_hamming_distance)) %>%
    ungroup()

  q_df_min_max <- q_df %>% pull(min_srr12) %>% max()
  q_df_max <- q_df %>% pull(max_srr12) %>% max()

  n_patients_bmpb <- q_df %>% pull(mmrf) %>% unique() %>% length()
  n_visits_bmpb <- q_df %>% nrow()
  cor_bmpb_n_fusions <- cor.test(q_df %>% pull(n_fusions_srr1), q_df %>% pull(n_fusions_srr2))

  q <- ggplot(data = q_df, aes(x = n_fusions_srr1, y = n_fusions_srr2)) +
    geom_abline(linetype = 2, color = "grey50") +
    geom_smooth(method = "lm") +
    geom_point(aes(size = overlap_srr12, color = igh_whsc1), shape = 16) +
    geom_point(aes(color = igh_whsc1), shape = 3, size = 2) +
    scale_color_brewer(palette = "Set2", drop = FALSE, direction = -1) +
    scale_size_area(breaks = c(0, 2, 4, 6, 8, 10)) +
    labs(x = "Number of Fusions (Bone Marrow)",
         y = "Number of Fusions (Peripheral Blood)",
         size = "Number of\nOverlapping\nFusion Calls",
         color = "IGH--WHSC1\nDetected") +
    theme_bw() +
    theme(plot.background = element_blank(),
          panel.background = element_blank(),
          panel.border = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text = element_text(size = 8),
          axis.ticks = element_blank(),
          axis.title = element_text(size = 10),
          legend.background = element_blank(),
          legend.text = element_text(size = 10))

  q_min_overlap <- ggplot(data = q_df, aes(x = min_srr12, y = overlap_srr12)) +
    geom_abline(linetype = 2, color = "grey50") +
    geom_smooth(method = "lm") +
    geom_point(aes(color = igh_whsc1), shape = 16) +
    geom_point(aes(color = igh_whsc1), shape = 3, size = 2) +
    scale_color_brewer(palette = "Set2", drop = FALSE, direction = -1) +
    scale_size_area(breaks = c(0, 2, 4, 6, 8, 10)) +
    labs(x = "Minimum Fusions (PB or BM)",
         y = "Overlapping Fusions (PB and BM)",
         size = "Number of\nOverlapping\nFusion Calls",
         color = "IGH--WHSC1\nDetected") +
    theme_bw() +
    xlim(0, q_df_min_max) + ylim(0, q_df_min_max) +
    theme(plot.background = element_blank(),
          panel.background = element_blank(),
          panel.border = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text = element_text(size = 8),
          axis.ticks = element_blank(),
          axis.title = element_text(size = 10),
          legend.background = element_blank(),
          legend.text = element_text(size = 10))

  q_lines <- ggplot(data = q_df %>%
                      mutate(patient_visit = factor(str_c(mmrf, first_srr, second_srr))) %>%
                      mutate(patient_visit = fct_reorder2(patient_visit, overlap_srr12 - max_srr12, overlap_srr12, .desc = TRUE)) %>%
                      mutate(patient_visit = fct_rev(patient_visit))) +
    geom_segment(aes(x = overlap_srr12,
                     xend = min_srr12,
                     y = patient_visit,
                     yend = patient_visit,
                     color = igh_whsc1)) +
    geom_segment(aes(x = n_fusions_srr1,
                     xend = n_fusions_srr2,
                     y = patient_visit,
                     yend = patient_visit,
                     color = igh_whsc1),
                 linetype = 3) +
    geom_point(aes(x = overlap_srr12,
                   y = patient_visit,
                   color = igh_whsc1),
               fill = "#ffffff",
               shape = 21,
               size = 3) +
    geom_point(aes(x = n_fusions_srr1, #BM
                   y = patient_visit,
                   color = igh_whsc1),
               shape = 16) +
    geom_point(aes(x = n_fusions_srr2, #PB
                   y = patient_visit,
                   color = igh_whsc1),
               shape = 4,
               size = 2) +
    geom_text(aes(y = patient_visit,
                  x = max_srr12,
                  label = round(normalized_hamming_distance, 2)),
              hjust = 0,
              nudge_x = 0.25) +
    scale_x_continuous(breaks = seq(0, q_df_max, 3)) +
    scale_color_brewer(palette = "Set2", drop = FALSE, direction = -1) +
    labs(x = "Number of Fusions",
         y = "Bone Marrow + Peripheral Blood Pair") +
    theme_bw() +
    theme(plot.background = element_blank(),
          panel.background = element_blank(),
          panel.border = element_blank(),
          panel.grid.minor = element_blank(),
          panel.grid.major.y = element_blank(),
          axis.text.x = element_text(size = 8),
          axis.text.y = element_blank(),
          axis.ticks = element_blank(),
          axis.title = element_text(size = 10),
          legend.background = element_blank(),
          legend.text = element_text(size = 10))
  ggsave(str_c(paper_main, "same_timepoints.bmpb.lines.no_legend.pdf"),
         q_lines + guides(size = FALSE, color = FALSE),
         device = "pdf", width = 2.75, height = 2.75, useDingbats = FALSE)
  ggsave(str_c(paper_main, "same_timepoints.bmpb.lines.pdf"),
         q_lines,
         device = "pdf", width = 2*2.75, height = 2.75, useDingbats = FALSE)

  ggsave(str_c(paper_main, "same_timepoints.bmpb.pdf"),
         q,
         device = "pdf", width = 2.75, height = 7.5, useDingbats = FALSE)
  ggsave(str_c(paper_main, "same_timepoints.bmpb.no_legend.pdf"),
         q + guides(size = FALSE, color = FALSE),
         device = "pdf", width = 2.75, height = 2.75, useDingbats = FALSE)
  ggsave(str_c(paper_supp, "same_timepoints.bmpb.min_overlap.pdf"),
         q_min_overlap,
         device = "pdf", width = 2.75, height = 7.5, useDingbats = FALSE)
  ggsave(str_c(paper_supp, "same_timepoints.bmpb.min_overlap.no_legend.pdf"),
         q_min_overlap + guides(size = FALSE, color = FALSE),
         device = "pdf", width = 2.75, height = 2.75, useDingbats = FALSE)

  # plot it
  keep_these_mmrfs <- fusions_all %>%
    filter(fusion %in% fusions_with_important_genes, has_secondary) %>%
    pull(mmrf) %>% unique()

  keep_these_srrs <- samples_all %>%
    group_by(mmrf) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    left_join(samples_all, by = "mmrf") %>%
    mutate(mmrf_srr = str_c(mmrf, srr, sep = ": ")) %>%
    group_by(mmrf) %>%
    mutate(ticker = row_number()) %>%
    select(mmrf, count, srr, visit, mmrf_srr, ticker, tissue_source) %>%
    ungroup() %>%
    filter(mmrf %in% keep_these_mmrfs)

  keep_these_srrs %>%
    left_join(fusions_all, by = c("mmrf", "srr")) %>%
    filter(fusion %in% fusions_with_important_genes) %>%
    right_join(keep_these_srrs, by = c("mmrf", "srr")) %>%
    mutate(mmrf_number_only = str_remove_all(mmrf, "MMRF_")) %>%
    replace_na(list(fusion = "Zero detected")) %>%
    left_join(tumor_purity %>% filter(Type == "RNA-Seq"), by = c("srr" = "SRR_Tumor")) %>%
    mutate(updated_srr = str_c(visit.y, tissue_source, format(round(TumorPurity, digits = 2), nsmall = 2), srr, sep = " ")) %>%
    ggplot(aes(y = fct_rev(factor(updated_srr)), x = fusion, fill = log10(FFPM + 1))) +
    geom_tile(color = "black") +
    geom_text(aes(label = visit.y), size = 1.75, vjust = 0.5) +
    theme_bw() +
    facet_wrap(~ mmrf_number_only , ncol = 1, strip.position = "left", dir = "h", scales = "free_y") +
    theme(panel.grid.major = element_line(size = 0.1),
          panel.border = element_rect(size = 0.1),
          axis.ticks = element_line(size = 0.1),
          strip.background = element_blank(),
          strip.placement = "outside",
          axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 5, face = "italic"),
          axis.text.y = element_text(angle = 0, hjust = 0.5, vjust = 0.5, size = 5),
          strip.text.y = element_text(angle = 180, size = 8),
          legend.position = "bottom",
          panel.spacing.y = unit(0.025, units = "inches")) +
    scale_fill_gradient(low = "#ffedbc", high = "#ed4264",
                        limits = c(0, 1.05),
                        breaks = seq(0, 1, 0.25),
                        labels = seq(0, 1, 0.25)) +
    scale_x_discrete(drop = FALSE) +
    labs(y = "Sample Number", x = NULL, fill = "Scaled FFPM") +
    ggsave(str_c(paper_supp, "multiple_timepoints.ffpm.pdf"),
           device = "pdf", width = 7.5, height = 9, useDingbats = FALSE)

  keep_these_srrs %>%
    left_join(fusions_all, by = c("mmrf", "srr")) %>%
    filter(fusion %in% fusions_with_important_genes) %>%
    right_join(keep_these_srrs, by = c("mmrf", "srr")) %>%
    mutate(mmrf_number_only = str_remove_all(mmrf, "MMRF_")) %>%
    replace_na(list(fusion = "Zero detected")) %>%
    left_join(tumor_purity %>% filter(Type == "RNA-Seq"), by = c("srr" = "SRR_Tumor")) %>%
    mutate(pct_to_use = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ geneB_pct,
                                  (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ geneA_pct)) %>%
    mutate(updated_fusion = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ str_c(fusion, "*"),
                                      (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ str_c(geneA, "*", "--", geneB),
                                      TRUE ~ fusion)) %>%
    mutate(updated_srr = str_c(visit.y, tissue_source, format(round(TumorPurity, digits = 2), nsmall = 2), srr, sep = " ")) %>%
    ggplot(aes(y = fct_rev(factor(updated_srr)), x = updated_fusion, fill = pct_to_use)) +
    geom_tile(color = "black") +
    geom_text(aes(label = visit.y), size = 1.75, vjust = 0.5) +
    theme_bw() +
    facet_wrap(~ mmrf_number_only , ncol = 1, strip.position = "left", dir = "h", scales = "free_y") +
    theme(panel.grid.major = element_line(size = 0.1),
          panel.border = element_rect(size = 0.1),
          axis.ticks = element_line(size = 0.1),
          strip.background = element_blank(),
          strip.placement = "outside",
          axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 5, face = "italic"),
          axis.text.y = element_text(angle = 0, hjust = 0.5, vjust = 0.5, size = 5),
          strip.text.y = element_text(angle = 180, size = 8),
          legend.position = "bottom",
          panel.spacing.y = unit(0.025, units = "inches")) +
    scale_fill_gradient(low = "#ffedbc", high = "#ed4264",
                        limits = c(0, 1.05),
                        breaks = seq(0, 1, 0.25),
                        labels = seq(0, 1, 0.25)
                        ) +
    scale_x_discrete(drop = FALSE) +
    labs(y = "Sample Number", x = NULL, fill = "Expression\nPercentile") +
    ggsave(str_c(paper_supp, "multiple_timepoints.expression_pct.pdf"),
           device = "pdf", width = 7.5, height = 9, useDingbats = FALSE)
}

# ==============================================================================
# Multiple time point fusions along with multiple exome seq mutations data
# ==============================================================================

if (TRUE) {

  fusion_samples_mtp <- samples_all %>%
    filter(tissue_source == "BM") %>%
    group_by(mmrf) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    left_join(samples_all, by = "mmrf") %>%
    arrange(mmrf, srr) %>%
    group_by(mmrf) %>%
    mutate(Tumor_Sample_Barcode = str_c(mmrf, "_", visit)) %>%
    select(mmrf, srr, visit, Tumor_Sample_Barcode) %>%
    mutate(data_type = "RNA", variant_type = "Fusion") %>%
    ungroup()

  snpindel_samples_mtp <- mutation_calls %>%
    arrange(Tumor_Sample_Barcode) %>%
    select(Tumor_Sample_Barcode, Matched_Norm_Sample_Barcode) %>%
    unique() %>%
    separate(Tumor_Sample_Barcode, into = c("mmrf1", "mmrf2", "visit"), sep = "_", remove = FALSE) %>%
    separate(Matched_Norm_Sample_Barcode, into = c("mmrf11", "mmrf22", "srr_normal", "srr", "N")) %>%
    mutate(visit = as.numeric(visit)) %>%
    mutate(mmrf = str_c(mmrf1, mmrf2, sep = "_"), data_type = "WES", variant_type = "SNP/INDEL") %>%
    select(mmrf, srr, visit, Tumor_Sample_Barcode, data_type, variant_type) %>%
    ungroup()

  overlap_once <- fusion_samples_mtp %>%
    left_join(snpindel_samples_mtp, by = c("mmrf", "visit", "Tumor_Sample_Barcode")) %>%
    filter(!is.na(srr.y))

  overlap_mtp <- overlap_once %>%
    group_by(mmrf) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    left_join(overlap_once, by = "mmrf")

  mtp_fusions <- overlap_mtp %>%
    select(mmrf, srr.x, visit, Tumor_Sample_Barcode, data_type.x, variant_type.x) %>%
    rename("srr" = "srr.x", "data_type" = "data_type.x", "variant_type" = "variant_type.x")

  mtp_mutations <- overlap_mtp %>%
    select(mmrf, srr.y, visit, Tumor_Sample_Barcode, data_type.y, variant_type.y) %>%
    rename("srr" = "srr.y", "data_type" = "data_type.y", "variant_type" = "variant_type.y")

  mtp_fusions_with_fusions <- fusions_all %>%
    filter(fusion %in% fusions_with_important_genes) %>%
    right_join(mtp_fusions, by = c("mmrf", "srr")) %>%
    mutate(pct_to_use = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ geneB_pct,
                                  (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ geneA_pct)) %>%
    mutate(updated_fusion = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ str_c(fusion, "*"),
                                      (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ str_c(geneA, "*", "--", geneB),
                                      TRUE ~ fusion)) %>%
    select(mmrf, visit, srr, data_type, variant_type, fusion, FFPM, geneA, geneB, geneA_pct, geneB_pct, pct_to_use, updated_fusion) %>%
    rename("variant" = "fusion", "detection_level" = "FFPM") %>%
    replace_na(list(variant = "Zero Detected"))

  mtp_mutations_with_mutations <- mutation_calls %>%
    filter(Hugo_Symbol %in% drivers_kinases_oncogenes_mmy_genes) %>%
    filter(Hugo_Symbol != "TTN") %>% # false positive
    separate(Tumor_Sample_Barcode, into = c("mmrf1", "mmrf2", "visit"), sep = "_", remove = FALSE) %>%
    mutate(visit = as.numeric(visit)) %>%
    separate(Matched_Norm_Sample_Barcode, into = c("mmrf11", "mmrf22", "srr_normal", "srr", "N")) %>%
    mutate(mmrf = str_c(mmrf1, mmrf2, sep = "_")) %>%
    right_join(mtp_mutations, by = c("mmrf", "srr", "visit")) %>%
    mutate(detection_level = t_alt_count/t_depth) %>%
    select(mmrf, visit, srr, data_type, variant_type, Hugo_Symbol, detection_level) %>%
    rename("variant" = "Hugo_Symbol")

  mmrf_to_plot <- c("MMRF_1433", "MMRF_1496", "MMRF_1656", "MMRF_2490")

  fusion_plot_df <- mtp_fusions_with_fusions %>%
    filter(mmrf %in% mmrf_to_plot) %>%
    group_by(mmrf, variant) %>%
    summarize(count = n()) %>%
    filter(count > 1) %>%
    left_join(mtp_fusions_with_fusions, by = c("mmrf", "variant"))

  mutation_plot_df_tp1 <- mtp_mutations_with_mutations %>%
    group_by(mmrf) %>%
    summarize(min_visit = min(visit)) %>%
    ungroup() %>%
    right_join(mtp_mutations_with_mutations, by = "mmrf") %>%
    filter(mmrf %in% mmrf_to_plot, visit == min_visit) %>%
    group_by(mmrf, visit, variant) %>%
    summarize(detection_level = mean(detection_level)) %>%
    ungroup()

  mutation_plot_df_tp2 <- mtp_mutations_with_mutations %>%
    group_by(mmrf) %>%
    summarize(min_visit = min(visit)) %>%
    ungroup() %>%
    right_join(mtp_mutations_with_mutations, by = "mmrf") %>%
    filter(mmrf %in% mmrf_to_plot, visit != min_visit) %>%
    group_by(mmrf, visit, variant) %>%
    summarize(detection_level = mean(detection_level)) %>%
    ungroup()

  mutation_plot_df <- mutation_plot_df_tp1 %>%
    full_join(mutation_plot_df_tp2, by = c("mmrf", "variant")) %>%
    replace_na(list(detection_level.x = 0, detection_level.y = 0)) %>%
    rowwise() %>%
    mutate(label_text = case_when(variant %in% mmy21 ~ variant))

  p <- ggplot(fusion_plot_df,
              aes(x = as.numeric(factor(visit)), y = variant)) +
    geom_point(aes(size = pct_to_use,
                   color = pct_to_use),
               shape = 16,
               show.legend = FALSE) +
    geom_text(aes(label = visit), size = 3, vjust = 0.5) +
    geom_text(data = fusion_plot_df %>% ungroup() %>% select(mmrf, updated_fusion, variant) %>% unique(),
              aes(label = updated_fusion, x = 1.5), nudge_y = 0.15,
              show.legend = FALSE, fontface = "italic") +
    facet_wrap(~mmrf, scales = "free", nrow = 1) +
    labs(y = NULL, x = NULL) +
    guides(size = FALSE) +
    scale_size_area(limits = c(0, 1.05)) +
    scale_color_gradient(low = "#ffedbc", high = "#ed4264",
                         limits = c(0,1.05),
                         breaks = seq(0, 1, 0.25),
                         labels = seq(0, 1, 0.25)) +
    theme_bw() +
    theme(panel.background = element_blank(),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.border = element_blank(),
          axis.text = element_blank(),
          axis.ticks = element_blank(),
          strip.background = element_blank(),
          strip.text = element_text(size = 10))

  q <- ggplot(mutation_plot_df,
              aes(x = detection_level.x,
                  y = detection_level.y,
                  color = label_text,
                  label = label_text)) +
    geom_abline(linetype = 2, color = "grey50") +
    geom_point(shape = 16) +
    geom_label_repel(fontface = "italic") +
    facet_wrap(~mmrf, nrow = 1) +
    labs(x = "Visit 1 Variant Allele Frequency (VAF)",
         y = "Visit 2, 3, or 4 VAF") +
    scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25),
                       labels = c("0", "0.25", "0.50", "0.75", "1.00")) +
    scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25),
                       labels = c("0", "0.25", "0.50", "0.75", "1.00")) +
    scale_color_brewer(palette = "Dark2", na.value = "#bdbdbd") +
    guides(color = FALSE) +
    theme_bw() +
    theme(panel.background = element_blank(),
          panel.grid.minor = element_blank(),
          panel.border = element_blank(),
          axis.ticks = element_blank(),
          strip.background = element_blank(),
          axis.text = element_text(size = 8),
          axis.title = element_text(size = 12))

  ggsave(str_c(paper_main, "fusions.pdf"), p + guides(color = FALSE),
         width = 7.25, height = 1.5, useDingbats = FALSE)

  ggsave(str_c(paper_main, "mutations.pdf"), q,
         width = 7.25, height = 2.25, useDingbats = FALSE)

  x <- keep_these_srrs %>%
    left_join(fusions_all, by = c("mmrf", "srr")) %>%
    filter(fusion %in% fusions_with_important_genes) %>%
    right_join(keep_these_srrs, by = c("mmrf", "srr")) %>%
    mutate(mmrf_number_only = str_remove_all(mmrf, "MMRF_")) %>%
    replace_na(list(fusion = "Zero detected")) %>%
    left_join(tumor_purity %>% filter(Type == "RNA-Seq"), by = c("srr" = "SRR_Tumor")) %>%
    mutate(pct_to_use = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ geneB_pct,
                                  (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ geneA_pct)) %>%
    mutate(updated_fusion = case_when((geneA %in% c("IGH", "IGK", "IGL") | geneB_oncogene | geneB_tsg | geneB_kinase | geneB_driver | drug_geneB) ~ str_c(fusion, "*"),
                                      (geneB %in% c("IGH", "IGK", "IGL") | geneA_oncogene | geneA_tsg | geneA_kinase | geneA_driver | drug_geneA) ~ str_c(geneA, "*", "--", geneB),
                                      TRUE ~ fusion)) %>%
    mutate(updated_srr = str_c(visit.y, tissue_source, format(round(TumorPurity, digits = 2), nsmall = 2), srr, sep = " ")) %>%
    filter(mmrf %in% mmrf_to_plot | mmrf == "MMRF_1496", tissue_source == "BM") %>%
    ggplot(aes(y = fct_rev(factor(updated_srr)), x = updated_fusion, fill = pct_to_use)) +
    geom_tile(color = "black") +
    geom_text(aes(label = visit.y), size = 3, vjust = 0.5) +
    theme_bw() +
    facet_wrap(~ mmrf_number_only , ncol = 1, strip.position = "left", dir = "h", scales = "free_y") +
    theme(panel.grid.major = element_line(size = 0.1),
          panel.border = element_rect(size = 0.1),
          axis.ticks = element_line(size = 0.1),
          strip.background = element_blank(),
          strip.placement = "outside",
          axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 10, face = "italic"),
          axis.text.y = element_text(angle = 0, hjust = 0.5, vjust = 0.5, size = 10),
          strip.text.y = element_text(angle = 180, size = 12),
          legend.position = "bottom",
          panel.spacing.y = unit(0.025, units = "inches")) +
    scale_fill_gradient(low = "#ffedbc", high = "#ed4264",
                        limits = c(0, 1.05),
                        breaks = seq(0, 1, 0.25),
                        labels = seq(0, 1, 0.25)
    ) +
    scale_x_discrete(drop = FALSE) +
    labs(y = "Sample Number", x = NULL, fill = "Expression\nPercentile")

  ggsave(str_c(paper_main, "multiple_timepoints.pdf"), x,
         device = "pdf", width = 7.25, height = 3.5, useDingbats = FALSE)
  ggsave(str_c(paper_main, "multiple_timepoints.no_legend.pdf"), x + guides(fill = FALSE),
         device = "pdf", width = 7.25, height = 3.5, useDingbats = FALSE)
}

# ==============================================================================
# Fusion multiple time points paragraph output
# ==============================================================================
n_mmrf_with_multiple_samples <- samples_all %>%
  group_by(mmrf) %>%
  summarize(count = n()) %>%
  filter(count > 1) %>%
  nrow()
pb_bm_overlap_assessment <- q_df %>%
  mutate(x = overlap_srr12/min_srr12) %>%
  filter(max_srr12 >= 3) %>%
  mutate(y = case_when(overlap_srr12/min_srr12 >= 2/3 ~ "Good Overlap",
                       TRUE ~ "Poor Overlap")) %>%
  pull(y) %>%
  table()

print(str_c("Number of patients with multiple samples: ", n_mmrf_with_multiple_samples))
print(str_c("Number of patients with two BM samples: ", n_patients_two_bm))
print("Table of IGH--WHSC1 fusions detected in BM samples:")
print(table_two_bm_ighwhsc1)
print("Info about patient with IGH--WHSC1 only at time point 2:")
print(info_tp1_ighwhsc1_falsenegative)
print(str_c("Number of patients with BM and PB samples: ", n_patients_bmpb))
print(str_c("Number of clinic visits for BM PB comparison: ", n_visits_bmpb))
print("Correlation between n_fusions BM TP1 TP2:")
print(cor_tp1tp2_n_fusions)
print("Correlation between n_fusions BM and PB: ")
print(cor_bmpb_n_fusions)
print("Overlap between PB and BM samples:")
print("Good and bad BM PB overlap:")
print(pb_bm_overlap_assessment)
print(pb_bm_overlap_assessment/sum(pb_bm_overlap_assessment))

