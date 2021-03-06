
library(Seurat)
library(loomR)
library(tidyverse)

library(reshape2)
library(data.table)
library(future)
library(furrr)
library(qs)

library(cocoframer)

library(ggsci)
library(cowplot)
library(viridis)
library(ComplexHeatmap)
library(pheatmap)
library(colorspace)
library(scales)

theme_set(theme_cowplot())



source("~/data2/rstudio/birds/utils/scRNA.R")
source("~/data2/rstudio/birds/utils/common_aesthetics.R")
source("~/data2/rstudio/birds/utils/go.R")
source("~/data2/rstudio/birds/utils/cocoframer_functions.R")
source("~/data2/rstudio/birds/utils/spatial_funcs.R")

# Directories -------------------------------------------------------------


dir_root = "~/data2/rstudio/birds/scRNA"
dev_dir = file.path(dir_root, "devin_combined", "finch_cells")
dev_data_dir = file.path(dir_root, "devin_combined", "data")
dev_out = file.path(dev_dir, "preprocessing", "integrate", "zf_bf", "joint2", "SCT_regress", "song")
dev_out_sub_dir = file.path(dev_out, sprintf("anchor%s_filter%s_score%s_maxfeatures%s_dims%s", 5, 200, 30, 200, 30))

tree_dir = file.path(dev_dir, "trees")
script_data_dir = file.path(tree_dir, "celltypes_hclust_glut_int_sub2_regress")


aba_data_dir = file.path("~/data2/aba")

out_dir = file.path(dev_dir, "comparative", "spatial")
script_name = "aba_ish_summary_glut_pallial"
out_dir = file.path(out_dir, script_name)
dir.create(out_dir)

data_out_obj_fname = file.path(script_data_dir, "obj_integrated_subclustered_glut.qs")
data_out_avg_fname = file.path(script_data_dir, "average_expr.qs")

assay_to_use = "SCT"
markers_fname = file.path(dev_out_sub_dir, sprintf("marker_genes_cluster_int_sub2_glut_%s.rds", assay_to_use))

tfs = get_tf_genes_human()

# Load data ---------------------------------------------------------------


obj_int_filt = qread(data_out_obj_fname) 
obj_int_filt = FindVariableFeatures(obj_int_filt, nfeatures = 6000)
var_genes = VariableFeatures(obj_int_filt)
genes_to_use = var_genes[var_genes %in% tfs$external_gene_name]

obj_int_avg1 = qread(data_out_avg_fname)
obj_int_avg1 = obj_int_avg1[rownames(obj_int_avg1) %in% tfs$external_gene_name,]


res_to_use = "cluster_int_sub2"
Idents(obj_int_filt) = obj_int_filt$cluster_int_sub2

# Load ABA reference ------------------------------------------------------

reference = get_ccf_annotation()
ref_dims = dim(reference)

grid_anno = get_ccf_grid_annotation()

# Load ontology -----------------------------------------------------------

ont = get_mba_ontology()
ont_df = flatten_mba_ontology(ont)
taxon = generate_mba_taxons(ont_df)
taxon_filt = filter_mba_ontology_children(ont_df, "CTX")
taxon_filt1 = taxon_filt %>% filter(st_level>6) %>%
  mutate(acronym = make.names(acronym))

taxon_filt2 = taxon_filt1 %>% 
  filter(!grepl("[a-z]", acronym))

# Process ontology --------------------------------------------------------


taxon_md = list("ACA" = c("meso", "M"),
                "AI" = c("meso", "L"),
                "AOB" = c("allo", "V"),
                "AON" = c("allo", "V"),
                "AUD" = c("neo", "D"),
                "BLA" = c("amyg", "A"),
                "BMA" = c("amyg", "A"),
                "CA" = c("allo", "M"),
                "CLA" = c("meso", "L"),
                "COA" = c("amyg", "A"),
                "DG" = c("allo", "M"),
                #"DP" = c("meso", "M"),
                "ECT" = c("meso", "L"),
                "ENT" = c("allo", "V"),
                "EP" = c("allo", "V"),
                "FRP" = c("neo", "D"),
                "GU" = c("neo", "D"),
                "ILA" = c("meso", "M"),
                "LA" = c("amyg", "A"),
                "MO[a-z]" = c("neo", "D"),
                "MOB" = c("allo", "V"), 
                "NLOT" = c("allo", "V"),
                "ORB" = c("neo", "D"),
                "PA$" = c("amyg", "A"),
                "PAA" = c("allo", "V"),
                "PAR" = c("allo", "M"),
                "PERI" = c("meso", "L"),
                "PIR" = c("allo", "V"),
                "PL" = c("meso", "M"),
                "POST" = c("allo", "M"),
                "PRE" = c("allo", "M"),
                "ProS" = c("allo", "M"),
                "PTL" = c("neo", "D"),
                "RSP" = c("meso", "M"),
                "SS" = c("neo", "D"),
                "SUB" = c("allo", "M"),
                "TE" = c("neo", "D"),
                "TR" = c("allo", "V"),
                "TT" = c("allo", "V"),
                "VIS" = c("neo", "D"),
                "VISC" = c("meso", "L")
                )

taxon_md_df = data.frame(prefix = names(taxon_md),
                         cortical = map_chr(taxon_md, 1),
                         pallial = map_chr(taxon_md, 2),
                         stringsAsFactors = F) %>%
  mutate(prefix = paste0("^", prefix))

taxon_md_terms = map(seq_along(taxon_md_df$prefix), function(i) {
  grep(taxon_md_df$prefix[i], taxon_filt1$acronym, value=T)
})
names(taxon_md_terms) = taxon_md_df$prefix
taxon_md_terms

taxon_md_terms_u = unlist(taxon_md_terms)
taxon_terms_df = tibble(prefix = names(taxon_md_terms),
                            acronym = taxon_md_terms)  %>%
  unnest(cols=c(acronym))


taxon_md_df  = taxon_md_df %>% left_join(taxon_terms_df)

taxon_md_df = taxon_md_df %>%
  mutate(pallial = factor(pallial, levels=c("D", "L", "M", "V", "A")),
         cortical = factor(cortical, levels=c("neo", "meso", "allo", "amyg")))

taxon_md_df = taxon_md_df %>% left_join(taxon_filt1)
taxon_md_df1 = taxon_md_df %>% filter(n_children==0)

# Load ABA ISH ------------------------------------------------------------

gene_id_fname = file.path(aba_data_dir, "gene_id.rds")
redo = F
if (redo) {
  gene_id = get_exp_gene_relationships()
  saveRDS(gene_id, gene_id_fname)
} else {
  gene_id = readRDS(gene_id_fname)
}

gene_id_filt = gene_id %>% 
  mutate(gene_symbol = toupper(gene_symbol)) %>%
  filter(gene_symbol %in% genes_to_use)
  

ish_dir = file.path(aba_data_dir, "ish_summaries")
dir.create(ish_dir)

plan(multisession(workers=4L, gc=T))
ishs = future_map(gene_id_filt$id, function(id) {
  ish_fname_cur = file.path(ish_dir, sprintf("%s.qs", id))
  print(id)
  if (! file.exists(ish_fname_cur)) {
    ish = get_aba_ish_structure_data(id)
    qsave(ish, ish_fname_cur)
  } else {
    ish = qread(ish_fname_cur)
  }
  ish 
}, .progress=T, .options=future_options(scheduling=10)) 
ishs = ishs %>%
  set_names(gene_id_filt$id) %>%
  bind_rows(.id="id") 

ishs = ishs %>% left_join(gene_id_filt)


ishs1 = ishs %>%
  mutate(acronym = make.names(acronym)) %>%
  group_by(gene_symbol, atlas_id, name, acronym) %>%
  summarize(energy_mean = mean(energy))
ish_mat = acast(ishs1, gene_symbol~acronym, value.var="energy_mean", fill=0)
ish_mat = ish_mat[,colnames(ish_mat) %in% taxon_filt1$acronym]
ish_mat_s = t(apply(ish_mat, 1, scale))
colnames(ish_mat_s) = colnames(ish_mat)
Heatmap(ish_mat_s)

sort(ish_mat["LHX9",], decreasing = F)
sort(ish_mat_s[,"VISam5"])

obj_int_avg2 = obj_int_avg1[rownames(obj_int_avg1) %in% rownames(ish_mat_s),]

# Correlate ---------------------------------------------------------------

mat_a = log1p(as.matrix(obj_int_avg2)) + .1
mat_b = log1p(ish_mat[,colnames(ish_mat) %in% taxon_md_df1$acronym]) + .1
obj_cor = region_correlate(mat_a, mat_b, method="spearman")

# Plot --------------------------------------------------------------------

pdf(file.path(out_dir,"finch_aba_cor.pdf"), height=20, width=5)
hm = Heatmap(t(obj_cor), clustering_method_rows = "ward.D")
print(hm)
dev.off()
hm
sort(obj_cor["RA_Glut-3", ])
sort(obj_cor["HVC_Glut-2", ])

# Shuffle -----------------------------------------------------------------

obj_cor_shuf_fname = file.path(out_dir, "obj_cor_shuf.qs")
redo = F
if (redo) {
  nrep = 100
  plan(multiprocess(workers=12, gc=T))
  obj_cor_shuf = future_map(1:nrep, function(i) {
    mat_a_cur = mat_a
    mat_b_cur = mat_b
    rownames(mat_a_cur) = sample(rownames(mat_a_cur))
    obj_cor = region_correlate(mat_a_cur, mat_b_cur)
    

    obj_cor_df = melt(obj_cor)
    colnames(obj_cor_df) =  c("celltype", "acronym", "value")
    obj_cor_df
  }) %>% bind_rows() 
  qsave(obj_cor_shuf, obj_cor_shuf_fname)
} else {
  obj_cor_shuf = qread(obj_cor_shuf_fname)
}

obj_cor_shuf_stat = obj_cor_shuf %>% group_by(celltype, acronym) %>%
  summarize(value_mean = mean(value),
            value_sd = sd(value),
            value_q99 = quantile(value, .99),
            value_q95 = quantile(value, .95))

obj_cor_df = melt(obj_cor)
colnames(obj_cor_df) = c("celltype", "acronym", "value")
obj_cor_df = obj_cor_df %>% left_join(obj_cor_shuf_stat)

obj_cor_df_filt = obj_cor_df %>% filter(value > value_q95)
obj_cor_df_filt_top = obj_cor_df_filt %>% group_by(celltype) %>% top_n(4, value)

# Write out correlations  -------------------------------------------------

out = obj_cor_df_filt_top %>% select(celltype, acronym, value)
colnames(out) = c("source", "target", "value")
write.table(out, file.path(out_dir, "cor_top4.txt"), sep="\t", row.names=F, quote=F)


out = obj_cor_df_filt %>% select(celltype, acronym, value) %>%
  arrange(celltype, desc(value))
colnames(out) = c("cluster", "region", "correlation")
write.table(out, file.path(out_dir, "cor_significant.txt"), sep="\t", row.names=F, quote=F)

# Plot filtered -----------------------------------------------------------

dat = acast(obj_cor_df, acronym~celltype, value.var="value", fill=0)

pdf(file.path(out_dir,"finch_aba_cor_filt.pdf"), height=20, width=5)
hm = Heatmap(dat, clustering_method_rows = "ward.D")
print(hm)
dev.off()
hm


# Correlation blocks ----------------------------------------------------------------

taxon_md_df2 = taxon_md_df1 %>%
  arrange(cortical, pallial) %>%
  ungroup() %>%
  mutate(prefix1 = sub("\\^", "", prefix),
         prefix1 = sub("\\$", "", prefix1)) %>%
  mutate(x = 1:n(),
         y = 1,
         xend = x,
         yend = y) %>%
  group_by(prefix1) %>%
  mutate(xend1 = mean(xend),
         taxon_width = n()) 

y_scale = .2
xmax = max(taxon_md_df2$x)
ymax = max(taxon_md_df2$x) * y_scale

width_scale = 20
finch_width = xmax / width_scale
finch_height = ymax / (width_scale * y_scale)  

corts = unique(taxon_md_df2$cortical)
cortical_colors = pal_locuszoom()(length(corts))
cortical_colors = brewer_pal(palette="Reds")(length(corts))
names(cortical_colors) = corts

pallial = unique(taxon_md_df2$pallial)
pallial_colors = pal_d3()(length(pallial))
pallial_colors = brewer_pal(palette="Purples")(length(pallial))
names(pallial_colors) = pallial

taxon_md_df2_un = taxon_md_df2 %>% 
  distinct(prefix1, yend, xend1, cortical, pallial, taxon_width) %>%
  mutate(cortical_color = cortical_colors[cortical],
         pallial_color = pallial_colors[pallial])

taxon_md_df2_un_cortical = taxon_md_df2 %>%
  ungroup() %>% 
  group_by(cortical) %>%
  summarize(xend2 = mean(xend1), yend = yend[1])

taxon_md_df2_un_pallial = taxon_md_df2 %>%
  ungroup() %>% 
  group_by(pallial) %>%
  summarize(xend2 = mean(xend1), yend = yend[1]) %>%
  ungroup() %>%
  mutate(pallial = case_when(pallial=="D" ~ "dorsal",
                             pallial=="L" ~ "lateral",
                             pallial=="M" ~ "medial",
                             pallial=="V" ~ "ventral",
                             pallial=="A" ~ "amyg"))

finch_samp = obj_cor_df %>% 
  distinct(celltype) %>%
  mutate(celltype = factor(celltype, levels=c("HVC_Glut-1", "HVC_Glut-4", "HVC_Glut-2", "HVC_Glut-3", "HVC_Glut-5", "RA_Glut-1", "RA_Glut-2", "RA_Glut-3"))) %>%
  arrange(celltype) %>% 
  mutate(x = seq(finch_width, max(taxon_md_df2$x) - finch_width, length.out = length(unique(celltype))),
         y = ymax) %>%
  mutate(position2 = str_extract(celltype, "^[A-Z]+")) %>%
  mutate(position2_color = position_pretty_colors2[position2]) %>%
  mutate(celltype_num = str_extract(celltype, "[0-9]$"))


size_scale = .01
obj_cor_seg =obj_cor_df %>%
  filter(value > value_q95) %>% 
  group_by(celltype) %>% 
  top_n(20, value) %>% 
  left_join(finch_samp) %>%
  left_join(taxon_md_df2 %>% select(acronym, prefix1, yend, xend, xend1)) %>%
  mutate(value_scale = value * size_scale) 

gg = ggplot() + 
  geom_segment(data=obj_cor_seg, aes(x=x, y=y, xend = xend, yend = yend+(finch_height/2) + (finch_height/2), size=value, color=position2_color), alpha=.5) +
  geom_tile(data=taxon_md_df2_un, aes(xend1, yend+(finch_height/2), fill=cortical_color, width=taxon_width, height=finch_height), color=1) + 
  geom_label(data=taxon_md_df2_un_cortical, aes(xend2, yend+(finch_height/2), label=cortical, ), fill="white", size=7/2.83, label.size=0) + 
  geom_tile(data=taxon_md_df2_un, aes(xend1, yend-(finch_height/2), fill=pallial_color, width=taxon_width, height=finch_height), color=1) + 
  geom_label(data=taxon_md_df2_un_pallial, aes(xend2, yend-(finch_height/2), label=pallial), fill="white", size=7/2.83, label.size=0) + 
  geom_tile(data=finch_samp, aes(x,y, width=finch_width, height=finch_height, fill=position2_color), color=1) + 
  geom_text(data=finch_samp, aes(x=x, y = y, label=celltype_num), size=7/2.83) + 
  scale_size_continuous(name = "rho", range=c(min(obj_cor_seg$value),max(obj_cor_seg$value))) + 
  scale_color_identity() + 
  scale_fill_identity() + 
  theme_void()

gg
save_plot(file.path(out_dir, "finch_aba_cor_subblocks.pdf"), gg, base_width=xmax /120, base_height = ymax/120)

gg_legend = get_legend(gg)
save_plot(file.path(out_dir, "finch_aba_cor_subblocks_legend.pdf"), gg_legend, base_width=5, base_height=5)

# Fraction pallium/cortex -----------------------------------------------------

taxon_md_df2 = taxon_md_df2 %>%
  mutate(pallial_cortical = paste(pallial, cortical, sep="_"))
obj_cor_df_filt_sum3 = region_calc_summary(obj_cor_df_cur, 
                                           taxon_md_df=taxon_md_df2,
                                           cor_quantile_filter = .95,
                                           value_n_quantile_filter = .95,
                                           grouping_factor_compare = "pallial_cortical",
                                           grouping_factor_data = "position2")

obj_cor_df_filt_sum3 = obj_cor_df_filt_sum3 %>%
  mutate(pallial_cortical = factor(pallial_cortical, levels=c("D_neo", "L_meso", "M_meso", "M_allo", "V_allo", "A_amyg"), labels=c("Neo", "L Meso", "M Meso", "M Allo", "V Allo", "Amyg")))

obj_cor_df_filt_sum3 = obj_cor_df_filt_sum3 %>%
  complete(pallial_cortical, position2, fill = list(value_n_n=0, value_n_n_fc_shuf=0))

obj_cor_df_filt_sum3 = obj_cor_df_filt_sum3 %>%
  mutate(sig = value_n_n>value_n_n_q95,
         sig_label = if_else(sig, "*", ""))

gg_pal_bar_v = ggplot(obj_cor_df_filt_sum3, aes(pallial_cortical, value_n_n_fc_shuf, color=position2, fill=position2)) + 
  geom_hline(yintercept=1, linetype=2, size=1/2.83) + 
  geom_bar(stat="identity", position=position_dodge(width = .75), width=.5) +
  scale_color_manual(name="", values=position_pretty_colors2, guide=F) +
  scale_fill_manual(name="", values=position_pretty_colors2, guide=F) +
  labs(x="Pallium", y = "observed / expected\nsignificant correlations") + 
  theme_cowplot() + 
  theme(legend.position=c(.5,.8),
        axis.text.y = element_text(size=7),
        axis.text.x = element_text(size=7, angle=30, hjust=1),
        axis.title = element_text(size=7),
        legend.text = element_text(size=7),
        axis.line = element_line(size=.5/2.83),
        axis.ticks = element_line(size=.5/2.83))  + 
  ylim(0, 5)
gg_pal_bar_v


save_plot(file.path(out_dir, "obs_exp_sig_cor_pallial-cortical_bar_vert.pdf"), gg_pal_bar_v, base_height=1.5, base_width=1.75)

gg_pal_bar_fv = ggplot(obj_cor_df_filt_sum3, aes(pallial_cortical, value_n_n_fc_shuf, color=position2, fill=position2)) + 
  geom_hline(yintercept=1, linetype=2, size=1/2.83) + 
  geom_bar(stat="identity", width=.5) +
  facet_grid(position2~.) +
  scale_color_manual(name="", values=position_pretty_colors2, guide=F) +
  scale_fill_manual(name="", values=position_pretty_colors2, guide=F) +
  labs(x="Pallium", y = "observed / expected\nsignificant correlations") + 
  theme_cowplot() + 
  theme(legend.position=c(.5,.8),
        axis.text.y = element_text(size=7),
        axis.text.x = element_text(size=7, angle=30, hjust=1),
        axis.title = element_text(size=7),
        legend.text = element_text(size=7),
        axis.line = element_line(size=.5/2.83),
        axis.ticks = element_line(size=.5/2.83),
        strip.text = element_blank(),
        strip.background = element_blank())  + 
  ylim(0, 5)
gg_pal_bar_fv


save_plot(file.path(out_dir, "obs_exp_sig_cor_pallial-cortical_bar_facet_vert.pdf"), gg_pal_bar_fv, base_height=1, base_width=1.5, nrow=2)

obj_cor_df_filt_sum3 = obj_cor_df_filt_sum3 %>%
  mutate(pallial_cortical = factor(pallial_cortical, levels=rev(levels(pallial_cortical)))) %>%
  mutate(position2 = factor(position2, levels=c("HVC", "RA")))

gg_pal_bar_f = ggplot(obj_cor_df_filt_sum3, aes(pallial_cortical, value_n_n_fc_shuf, color=position2, fill=position2)) + 
  geom_bar(stat="identity", width=.5) +
  geom_hline(yintercept=1, linetype=2, size=1/2.83) + 
  facet_grid(.~position2) +
  coord_flip() +
  scale_color_manual(name="", values=position_pretty_colors2, guide=F) +
  scale_fill_manual(name="", values=position_pretty_colors2, guide=F) +
  labs(x="Pallium", y = "observed / expected\nsignificant correlations") + 
  theme_cowplot() + 
  theme(legend.position=c(.5,.8),
        axis.text = element_text(size=7),
        axis.title = element_text(size=7),
        legend.text = element_text(size=7),
        axis.line = element_line(size=.5/2.83),
        axis.ticks = element_line(size=.5/2.83),
        strip.text = element_blank(),
        strip.background = element_blank())  + 
  ylim(0, 6)
gg_pal_bar_f


save_plot(file.path(out_dir, "obs_exp_sig_cor_pallial-cortical_bar_facet.pdf"), gg_pal_bar_f, base_height=1.2, base_width=1, ncol=2)

saveRDS(obj_cor_df_filt_sum3, file.path(out_dir, "compare_pallial_stats.rds"))

# Map cor to anno ---------------------------------------------------------

taxon_filt_cur = taxon_filt %>% 
  mutate(acronym = make.names(acronym)) %>%
  select(acronym, id)
obj_cor_df_filt1 = obj_cor_df %>% left_join(taxon_filt_cur)
obj_cor_id = obj_cor
colnames(obj_cor_id) = taxon_filt$id[match(colnames(obj_cor), taxon_filt$acronym)]
obj_cor_id = obj_cor_id[,!is.na(colnames(obj_cor_id))]
unique_ids = as.numeric(colnames(obj_cor_id))
unique_cts = rownames(obj_cor)
grid_anno_cors = map(seq_along(unique_cts), function(i) array(NA, dim=dim(reference))) %>%
  set_names(unique_cts)

ref_dt = as.data.table(reference)
setkey(ref_dt, value)
for (ct in unique_cts) {
  print(ct)
  obj_cor_df_cur = obj_cor_df_filt1 %>% filter(celltype==ct)
  unique_ids = unique(obj_cor_df_cur$id)
  for (i in unique_ids) {
    obj_cor_df_cur1 = obj_cor_df_cur %>% filter(id==i)
    inds = as.matrix(ref_dt[.(i), .(V1, V2, V3)])
    grid_anno_cors[[ct]][inds] = obj_cor_df_cur1$value[1]
  }
}

obj_cor_df_top = obj_cor_df_filt1 %>% 
  filter(value>value_q95) %>% 
  group_by(celltype) %>%
  top_n(10, value)

# Calculate median positions ----------------------------------------------

ref_dt_med = ref_dt %>% group_by(value) %>% 
  summarize(X = median(V1),
            Y = median(V2),
            Z = median(V3)) %>%
  rename(id = value) %>% 
  left_join(taxon_filt %>% select(id, acronym))
ref_dt_med %>% filter(acronym=="RSPv1")
taxon_filt %>% filter(id==60)


# Plot correlations on ABA ---------------------------------------------------------

plane = "coronal"
resolution = 10
cts = rev(unique(obj_cor_df_filt1$celltype))
slices = seq(10, 400, resolution)
map(cts, function(ct) {
  print(ct)
  out_ct_dir = file.path(out_dir, ct)
  dir.create(out_ct_dir)
  
  map(slices, function(slice_num) {
    print(slice_num)
  ish_plot = ish_slice_heatmap_flat(mat=grid_anno_cors[[ct]],
                                    anno = reference,
                                    taxon = taxon_filt,
                                    slice_num = slice_num,
                                    plane = plane,
                                    normalize = "all",
                                    colorset = c(brewer_pal(palette= "Blues")(9)[c(1,9)])
  ) + 
    labs(title=ct)
  
  if (plane=="coronal") {
    height = dim(reference)[2] * .01
    width = dim(reference)[3] * .01
  }
  
  save_plot(file.path(out_ct_dir, sprintf("ish_%s_%s_%s.pdf", ct, plane, slice_num)),
            ish_plot,
            base_height=height,
            base_width=width)
  
  })
})

# get ABA SVGS ----------------------------------------------------------------

library(curl)
aba_ids = get_aba_adult_mouse_ids()

 out_svg_dir = file.path(aba_data_dir, "aba_reference_svgs")
dir.create(out_svg_dir)

save_aba_svgs(aba_ids, out_dir = out_svg_dir, downsample = 2, remove_colors=F)
