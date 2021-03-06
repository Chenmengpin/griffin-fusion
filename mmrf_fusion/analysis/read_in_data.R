# ==============================================================================
# Reads in data for analysis
# Steven Foltz (github: envest)
# ==============================================================================

# ==============================================================================
# Load all packages at beginning
# ==============================================================================

library(ggrepel)
library(gridExtra)
library(RColorBrewer)
library(readxl)
library(Seurat)
library(survival)
library(survminer)
library(tidyverse)
library(UpSetR)
library(viridis)

# ==============================================================================
# Sample lists (MMRF, SRR) of data related to samples in this analysis
# ==============================================================================

samples_all <- read_tsv("data/sample_list.806.fixed_visit_number.txt",
                        col_names = c("mmrf", "srr", "visit", "tissue_source"))
samples_primary <- read_tsv("data/sample_list.primary.txt",
                            col_names = c("mmrf", "srr"))

# ==============================================================================
# Fusion tibbles. fusions_primary contains fusions from primary time points
# This is BEFORE removing significantly undervalidated fusions
# ==============================================================================

fusions_all <- read_tsv("data/fusion_df.txt") %>%
  mutate(fusion = str_remove(fusion, "@"),
         geneA = str_remove(geneA, "@"),
         geneB = str_remove(geneB, "@"))
fusions_primary <- fusions_all %>% filter(srr %in% samples_primary$srr)

# ==============================================================================
# Flag and remove potential false positives (significantly undervalidated)
# This REMOVES significantly undervalidated fusions from fusions data frames
# ==============================================================================

wgs_discordant_read_validation_rate <- fusions_primary %>% 
  filter(!is.na(n_discordant), 
         Overlap != "Overlapping_regions") %>% 
  mutate(validated = n_discordant >= 3) %>% # require 3 or more discordant reads
  pull(validated) %>%
  mean()

significantly_under_validated_fusions <- fusions_primary %>% 
  filter(!is.na(n_discordant), Overlap != "Overlapping_regions") %>% 
  mutate(validated = n_discordant >= 3) %>% 
  group_by(fusion) %>% 
  summarize(n = n(), n_validated = sum(validated)) %>%
  arrange(desc(n)) %>%
  mutate(p_value = pbinom(q = n_validated, size = n, 
                          prob = wgs_discordant_read_validation_rate)) %>% 
  filter(p_value < 0.15) %>% 
  pull(fusion)

undervalidated <- fusions_all %>% 
  filter(fusion %in% significantly_under_validated_fusions) %>%
  group_by(fusion, geneA, geneB) %>%
  summarize(fusion_count = n()) %>%
  ungroup() %>%
  mutate(filter = "Undervalidated") %>%
  rename("FusionName" = "fusion")

fusions_all <- fusions_all %>% 
  filter(!(fusion %in% significantly_under_validated_fusions))
fusions_primary <- fusions_primary %>% 
  filter(!(fusion %in% significantly_under_validated_fusions))

# ==============================================================================
# TCGA pan-cancer paper Low Pass similar coverage validation rate
# ==============================================================================

tcga_validation_rate_df <- read_tsv("data/tcga_pancancer_fusions.validation.txt")
n_fusions_validated_tcga <- tcga_validation_rate_df %>% 
  filter(Distance == 100000,     # Distance threshold used in pan-cancer paper 
         Coverage == "LowPass",  # Low pass data
         ReadsCount < 200,       # Eliminate overlapping regions
         ReadsCount >= 3) %>%    # Require 3 or more reads
  nrow()
n_fusions_with_wgs_tcga <- tcga_validation_rate_df %>% 
  filter(Distance == 100000, 
         Coverage == "LowPass", 
         ReadsCount < 200, 
         ReadsCount >= 0) %>% 
  nrow()
tcga_validation_rate <- n_fusions_validated_tcga/n_fusions_with_wgs_tcga

# ==============================================================================
# seqFISH and clinical information
# ==============================================================================

updated_clinical <- read_csv("data/Clinical_data.20190913.csv") %>% 
  select("Spectrum_Seq", "public_id", "del17p", "amp1q", "HRD", # here HRD = High Risk Disease
         "ECOG", "Plasma_Cell_Percent", "ISS", "LDH", "Bone_Lesions", "Plasmacytoma", 
         "Age", "EFS", "EFS_censor","OS", "OS_censor", 
         "Female", "White", "AA_Black", "Other_race",
         "D_PT_therclass", "BMT") %>% 
  rename("mmrf" = "public_id", "BM_Plasma_Cell_Percent" = "Plasma_Cell_Percent",
         "ISS_Stage" = "ISS", "Bone_lesions" = "Bone_Lesions", 
         "Race_White" = "White", "Race_Black" = "AA_Black", "Race_Other" = "Other_race") %>% 
  mutate(age_ge_66 = Age >= 66, 
         race = Race_White + 2*Race_Black + 3*Race_Other) %>% 
  mutate(early_relapse_time = case_when(EFS < 540 ~ EFS,
                                        TRUE ~ 540),
         early_relapse_censor = case_when(EFS >= 540 ~ 1,
                                          TRUE ~ EFS_censor)) %>%
  filter(mmrf %in% samples_primary$mmrf)

once_only_clinical <- updated_clinical %>% 
  group_by(mmrf) %>% 
  summarize(count = n()) %>% 
  filter(count == 1) %>% 
  pull(mmrf)

updated_clinical <- updated_clinical %>% # reduce to only one row per patient
  filter(mmrf %in% once_only_clinical | Spectrum_Seq == str_c(mmrf, "_1")) %>%
  right_join(samples_primary %>% select(mmrf), by = "mmrf") %>%
  rename("seqfish_Study_Visit_ID" = "Spectrum_Seq") %>%
  mutate(seqfish_Study_Visit_ID = str_c(seqfish_Study_Visit_ID, "_BM"))

updated_cnv <- read_tsv("data/MMRF_CoMMpass_IA14a_CNA_LongInsert_FISH_CN_All_Specimens.txt") %>% 
  select(Study_Visit_ID, 
         ends_with("20percent"), # CNV indicator
         SeqWGS_Cp_Hyperdiploid_Call) %>% # Hyperdiploid indicator
  rename("seqfish_Study_Visit_ID" = "Study_Visit_ID")

updated_seqfish_IGHKL <- read_tsv("data/MMRF_CoMMpass_IA14a_LongInsert_Canonical_Ig_Translocations.txt") %>%
  mutate(updated_seqfish_t_IGH_WHSC1 = case_when(SeqWGS_WHSC1_CALL == 1 & SeqWGS_WHSC1_iGSOURCE == 1 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGK_WHSC1 = case_when(SeqWGS_WHSC1_CALL == 1 & SeqWGS_WHSC1_iGSOURCE == 2 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGL_WHSC1 = case_when(SeqWGS_WHSC1_CALL == 1 & SeqWGS_WHSC1_iGSOURCE == 3 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGH_CCND3 = case_when(SeqWGS_CCND3_CALL == 1 & SeqWGS_CCND3_iGSOURCE == 1 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGK_CCND3 = case_when(SeqWGS_CCND3_CALL == 1 & SeqWGS_CCND3_iGSOURCE == 2 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGL_CCND3 = case_when(SeqWGS_CCND3_CALL == 1 & SeqWGS_CCND3_iGSOURCE == 3 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGH_MYC = case_when(SeqWGS_MYC_CALL == 1 & SeqWGS_MYC_iGSOURCE == 1 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGK_MYC = case_when(SeqWGS_MYC_CALL == 1 & SeqWGS_MYC_iGSOURCE == 2 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGL_MYC = case_when(SeqWGS_MYC_CALL == 1 & SeqWGS_MYC_iGSOURCE == 3 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGH_MAFA = case_when(SeqWGS_MAFA_CALL == 1 & SeqWGS_MAFA_iGSOURCE == 1 ~ 1,
                                                TRUE ~ 0),
         updated_seqfish_t_IGK_MAFA = case_when(SeqWGS_MAFA_CALL == 1 & SeqWGS_MAFA_iGSOURCE == 2 ~ 1,
                                                TRUE ~ 0),
         updated_seqfish_t_IGL_MAFA = case_when(SeqWGS_MAFA_CALL == 1 & SeqWGS_MAFA_iGSOURCE == 3 ~ 1,
                                                TRUE ~ 0),
         updated_seqfish_t_IGH_CCND1 = case_when(SeqWGS_CCND1_CALL == 1 & SeqWGS_CCND1_iGSOURCE == 1 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGK_CCND1 = case_when(SeqWGS_CCND1_CALL == 1 & SeqWGS_CCND1_iGSOURCE == 2 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGL_CCND1 = case_when(SeqWGS_CCND1_CALL == 1 & SeqWGS_CCND1_iGSOURCE == 3 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGH_CCND2 = case_when(SeqWGS_CCND2_CALL == 1 & SeqWGS_CCND2_iGSOURCE == 1 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGK_CCND2 = case_when(SeqWGS_CCND2_CALL == 1 & SeqWGS_CCND2_iGSOURCE == 2 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGL_CCND2 = case_when(SeqWGS_CCND2_CALL == 1 & SeqWGS_CCND2_iGSOURCE == 3 ~ 1,
                                                 TRUE ~ 0),
         updated_seqfish_t_IGH_MAF = case_when(SeqWGS_MAF_CALL == 1 & SeqWGS_MAF_iGSOURCE == 1 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGK_MAF = case_when(SeqWGS_MAF_CALL == 1 & SeqWGS_MAF_iGSOURCE == 2 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGL_MAF = case_when(SeqWGS_MAF_CALL == 1 & SeqWGS_MAF_iGSOURCE == 3 ~ 1,
                                               TRUE ~ 0),
         updated_seqfish_t_IGH_MAFB = case_when(SeqWGS_MAFB_CALL == 1 & SeqWGS_MAFB_iGSOURCE == 1 ~ 1,
                                                TRUE ~ 0),
         updated_seqfish_t_IGK_MAFB = case_when(SeqWGS_MAFB_CALL == 1 & SeqWGS_MAFB_iGSOURCE == 2 ~ 1,
                                                TRUE ~ 0),
         updated_seqfish_t_IGL_MAFB = case_when(SeqWGS_MAFB_CALL == 1 & SeqWGS_MAFB_iGSOURCE == 3 ~ 1,
                                                TRUE ~ 0) ) %>% 
  select(Study_Visit_iD, starts_with("updated_seqfish_t_IG")) %>%
  rename("seqfish_Study_Visit_ID" = "Study_Visit_iD")

n_fusions_tibble <- fusions_primary %>% 
  group_by(mmrf) %>% 
  summarize(total_fusions = n())

seqfish_clinical_info <- updated_clinical %>% 
  left_join(updated_seqfish_IGHKL, 
            by = "seqfish_Study_Visit_ID") %>%
  left_join(updated_cnv, 
            by = "seqfish_Study_Visit_ID") %>%
  left_join(n_fusions_tibble, 
            by = "mmrf") %>% 
  replace_na(list(total_fusions = 0)) %>%
  mutate(total_fusions_high = case_when(total_fusions > 4 ~ 1,
                                        TRUE ~ 0)) %>%
  mutate_at(c("Female", "Race_White", "Race_Black", "Race_Other", "race", 
              "ECOG", "ISS_Stage", "Bone_lesions", "Plasmacytoma"), as.factor)

# Samples whose primary timepoint is also pre-treatment

mmrf_primary_pretreatment <- samples_primary %>% 
  left_join(samples_all, by = c("mmrf", "srr")) %>% 
  filter(visit == 1) %>% 
  pull(mmrf)

rm(updated_clinical)
rm(once_only_clinical)
rm(updated_seqfish_IGHKL)
rm(updated_cnv)
rm(n_fusions_tibble)

# ==============================================================================
# Gene expression data
# ==============================================================================

# read in expression data but only keep data from samples in analysis
expression_all <- read_tsv("data/mmy_gene_expr_with_fusions.tsv") %>%
  filter(srr %in% samples_all$srr)

# keep primary samples only
expression_primary <- expression_all %>% filter(srr %in% samples_primary$srr)

# ==============================================================================
# Information about kinases
# ==============================================================================

kinases <- read_tsv("data/Kinase_fusion_info.txt") %>% 
  mutate(Fusion = str_remove(Fusion, "@")) %>% 
  right_join(fusions_primary, by = c("PatientID" = "mmrf", 
                                     "SampleID" = "srr", 
                                     "Fusion" = "fusion")) %>% 
  filter(!is.na(KinaseDomain)) %>%
  mutate(kinase_group_full_name = case_when(Group == "TK" ~ "Tyrosine\nKinase",
                                            Group == "OTHER" ~ "Other",
                                            Group == "TKL" ~ "Tyrosine\nKinase-Like",
                                            TRUE ~ Group))

# ==============================================================================
# Sample output file locations
# ==============================================================================
file_locations <- read_tsv("data/sample_list.with_file_names.txt",
                           col_names = FALSE)

# ==============================================================================
# ENSG gene names
# ==============================================================================

# read in list of ENSGs and gene names used in this study
#ensg_gene_list <- read_tsv("data/ensg_gene_list.tsv")

# ==============================================================================
# TCGA Pan-cancer fusion analysis results
# ==============================================================================

pancan_fusions <- read_excel("data/tcga_pancancer_fusions.xlsx",
                             sheet = "Final fusion call set")
names(pancan_fusions) <- as.character(pancan_fusions[1,])
pancan_fusions <- pancan_fusions[-1,]

# ==============================================================================
# DEPO database
# ==============================================================================

depo <- read_tsv("data/DEPO_final_20170206.txt")

# ==============================================================================
# Soft filtering
# ==============================================================================

soft_columns <- c("FusionName",	"LeftBreakpoint",	"RightBreakpoint", "Cancer", 
                  "Sample", "JunctionReadCount", "SpanningFragCount", "FFPM", 
                  "PROT_FUSION_TYPE", "GTEx", "Callers", "CallerNumber")
efi <- read_tsv("data/Fusions_EFI.tsv", col_names = soft_columns)
efi <- efi %>% mutate(filter = "EFI")
low_count <- read_tsv("data/Fusions_low_count.tsv", col_names = soft_columns)
low_count <- low_count %>% mutate(filter = "Low Count")
many_partners <- read_tsv("data/Fusions_with_many_partners.tsv", col_names = soft_columns)
many_partners <- many_partners %>% mutate(filter = "Many Partners")
within_300kb <- read_tsv("data/Fusions_within_300kb.tsv", col_names = soft_columns)
within_300kb <- within_300kb %>% mutate(filter = "Within 300Kb")
soft_filtered <- bind_rows(efi, low_count, many_partners, within_300kb)

rm(soft_columns)
rm(efi)
rm(low_count)
rm(many_partners)
rm(within_300kb)

# ==============================================================================
# Mutation calls from Hua
# ==============================================================================

mutation_calls <- read_tsv("data/wxs_bm_data.withmutect.merged.maf.rc.caller.renamed.Bone_Marrow.tsv",
                           col_types = cols_only(Hugo_Symbol = "c",
                                                 Chromosome	= "n",
                                                 Start_Position	= "n",
                                                 End_Position	= "n",
                                                 Variant_Classification = "c",
                                                 Variant_Type = "c",
                                                 Reference_Allele	= "c",
                                                 Tumor_Seq_Allele1 = "c",
                                                 Tumor_Seq_Allele2 = "c",
                                                 Tumor_Sample_Barcode	= "c",
                                                 Matched_Norm_Sample_Barcode = "c",
                                                 HGVSc	= "c",
                                                 HGVSp	= "c",
                                                 HGVSp_Short = "c",
                                                 Transcript_ID = "c",
                                                 t_depth = "n",
                                                 t_ref_count = "n",
                                                 t_alt_count = "n",
                                                 Consequence = "c",
                                                 CLIN_SIG = "c",
                                                 IMPACT = "c"))

# ==============================================================================
# Mutational signature info from Yize
# ==============================================================================

mut_initial <- mutation_calls %>% select(Tumor_Sample_Barcode, Matched_Norm_Sample_Barcode) %>% 
  unique() %>% 
  separate(Tumor_Sample_Barcode, into = c("MMRF1", "MMRF_num1", "visit"), sep = "_") %>%
  separate(Matched_Norm_Sample_Barcode, into = c("MMRF2", "MMRF_num2", "SRR1", "SRR2", "N")) %>%
  mutate(visit = as.numeric(visit))

mutsig_initial <- read_excel("data/Table1.MMRF_signature.xlsx",
                     sheet = "Fraction") %>%
  separate(ID, into = c("MMRF2", "MMRF_num2", "SRR1", "SRR2", "T"), sep = "_")

mutsig <- mutsig_initial %>% 
  left_join(mut_initial, by = c("MMRF_num2", "SRR1", "SRR2")) %>% 
  filter(!is.na(visit)) %>% 
  mutate(mmrf = str_c(MMRF2.x, MMRF_num2, sep = "_")) %>% 
  select(mmrf, visit, W1, W2) %>% 
  left_join(samples_all %>% filter(srr %in% samples_primary$srr), 
            by = c("mmrf", "visit")) %>% 
  filter(!is.na(srr)) %>%
  rename("APOBEC" = "W1") %>%
  rename("Signature5" = "W2") %>%
  select(mmrf, srr, visit, APOBEC, Signature5)

rm(mut_initial)
rm(mutsig_initial)

# ==============================================================================
# Sample names used by Hua
# ==============================================================================

matched_names <- read_tsv("data/sample_infor.v20170912.plus.v4.matchedName.All.out")

# ==============================================================================
# Tumor purity estimates from Hua
# ==============================================================================

tumor_purity <- read_tsv("data/MMRF_estimate_score.tsv") %>% 
  left_join(matched_names, by = c("MMRF" = "SampleID_Tumor"))

# ==============================================================================
# Important genes
# ==============================================================================

drivers <- read_tsv("data/driver.tsv", col_names = FALSE)
kinases2 <- read_tsv("data/kinase.tsv", col_names = FALSE)
mmy_known <- read_tsv("data/mmy_known.tsv", col_names = FALSE)
oncogenes <- read_tsv("data/oncogene.tsv", col_names = FALSE)
mmy21 <- c("KRAS", "NRAS", "FAM46C", "BRAF", "TP53", "DIS3", "PRDM1", "SP140",
           "EGR1", "TRAF3", "ATM", "CCDN1", "HIST1E", "LTB", "IRF4", "FGFR3",
           "RB1", "ACTG1", "CYLD", "MAX", "ATR")
drivers_kinases_oncogenes_mmy_genes <- unique(sort(c(drivers$X1, kinases2$X1, oncogenes$X1, mmy21)))

# ==============================================================================
# scRNA analysis
# ==============================================================================

#scRNA.sample_barcode_celltype.txt
gene_spans <- read_tsv("data/ref_annot.gtf.gene_spans",
                       col_names = c("ENSG", "chromosome", "start", "end", 
                                     "strand", "gene_name", "type"))

# Chimeric reads from bulk RNA
Chimeric.out.junction.column_names <- c("chromosome_donor",
                                        "first_base_intron_donor",
                                        "strand_donor",
                                        "chromosome_acceptor",
                                        "first_base_intron_acceptor",
                                        "strand_acceptor",
                                        "junction_type",
                                        "repeat_length_left",
                                        "repeat_length_right",
                                        "read_name",
                                        "first_base_donor",
                                        "CIGAR_donor",
                                        "first_base_acceptor",
                                        "CIGAR_acceptor",
                                        "V15", "V16")
#Chimeric.out.junction column names from:
#https://groups.google.com/forum/#!msg/rna-star/HUxFCaHSX6c/iSudPgceUXkJ

bulk_reads_27522_1 <- read_tsv("data/scRNA.27522_1.bulk.chr414.Chimeric.out.junction",
                               col_names = Chimeric.out.junction.column_names)
bulk_reads_27522_4 <- read_tsv("data/scRNA.27522_4.bulk.chr414.Chimeric.out.junction",
                               col_names = Chimeric.out.junction.column_names)

# STAR-Fusion calls (only 27522_1 relevant fusions detected)
star_fusion_calls_27522_1 <- read_tsv("data/scRNA.27522_1.bulk.star-fusion.fusion_predictions.tsv")

# scRNA inferCNV results
infercnv_27522_1 <- read_tsv("data/scRNA.27522_1.infercnv.observations.txt")
infercnv_27522_4 <- read_tsv("data/scRNA.27522_4.infercnv.observations.txt")

# scRNA cell types
cell_types_27522_1 <- read_tsv("data/scRNA.cell_types.27522_1.tsv")
cell_types_27522_4 <- read_tsv("data/scRNA.cell_types.27522_4.tsv")

# discordant reads
dis_reads_27522_1_discover <- read_tsv("data/scRNA.discordant_reads.discover.27522_1.tsv") %>% mutate(supports = "t(4;14)")
dis_reads_27522_1_discover_preQC <- read_tsv("data/scRNA.discordant_reads.discover.27522_1.preQC.tsv") %>% mutate(supports = "t(4;14)")
dis_reads_27522_4_discover <- read_tsv("data/scRNA.discordant_reads.discover.27522_4.tsv") %>% mutate(supports = "t(4;14)")

# Seurat objects, run UMAP
seurat_object_27522_1 <- RunUMAP(UpdateSeuratObject(read_rds("data/scRNA.seurat_object.27522_1.rds")), dims = 1:20)
seurat_object_27522_4 <- RunUMAP(UpdateSeuratObject(read_rds("data/scRNA.seurat_object.27522_4.rds")), dims = 1:20)
