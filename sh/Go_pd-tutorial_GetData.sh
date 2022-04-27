#!/bin/bash
###
# https://docs.qiime2.org/2022.2/tutorials/pd-mice/

cwd=$(pwd)

DATADIR="${cwd}/data"

###
wget -O "${DATADIR}/metadata.tsv" \
	"https://data.qiime2.org/2022.2/tutorials/pd-mice/sample_metadata.tsv"
###
# From https://docs.qiime2.org/2022.2/install/native/
# wget https://data.qiime2.org/distro/core/qiime2-2022.2-py38-osx-conda.yml
# conda env create -n qiime2 --file qiime2-2022.2-py38-osx-conda.yml
###
if [ ! "$CONDA_EXE" ]; then
	CONDA_EXE=$(which conda)
fi
if [ ! "$CONDA_EXE" -o ! -e "$CONDA_EXE" ]; then
	echo "ERROR: conda not found."
	exit
fi
source $(dirname $CONDA_EXE)/../bin/activate qiime2
###
qiime metadata tabulate \
	--m-input-file ${DATADIR}/metadata.tsv \
	--o-visualization ${DATADIR}/metadata.qzv
#
wget -O "${DATADIR}/manifest.tsv" \
	"https://data.qiime2.org/2022.2/tutorials/pd-mice/manifest"
#
wget -O "${DATADIR}/demultiplexed_seqs.zip" \
	"https://data.qiime2.org/2022.2/tutorials/pd-mice/demultiplexed_seqs.zip"
#
(cd $DATADIR; unzip demultiplexed_seqs.zip)
#
###
# Importing data into QIIME 2
qiime tools import \
	--type "SampleData[SequencesWithQuality]" \
	--input-format SingleEndFastqManifestPhred33V2 \
	--input-path ${DATADIR}/manifest.tsv \
	--output-path ${DATADIR}/demux_seqs.qza
#
qiime demux summarize \
	--i-data ${DATADIR}/demux_seqs.qza \
	--o-visualization ${DATADIR}/demux_seqs.qzv
#
# Sequence quality control and feature table
qiime dada2 denoise-single \
	--i-demultiplexed-seqs ${DATADIR}/demux_seqs.qza \
	--p-trunc-len 150 \
	--o-table ${DATADIR}/dada2_table.qza \
	--o-representative-sequences ${DATADIR}/dada2_rep_set.qza \
	--o-denoising-stats ${DATADIR}/dada2_stats.qza
#
qiime metadata tabulate \
	--m-input-file ${DATADIR}/dada2_stats.qza  \
	--o-visualization ${DATADIR}/dada2_stats.qzv
#
# Feature table summary
qiime feature-table summarize \
  --i-table ./dada2_table.qza \
  --m-sample-metadata-file ./metadata.tsv \
  --o-visualization ./dada2_table.qzv
#
# Generating a phylogenetic tree for diversity analysis
wget \
  -O "sepp-refs-gg-13-8.qza" \
  "https://data.qiime2.org/2022.2/common/sepp-refs-gg-13-8.qza"
#
qiime fragment-insertion sepp \
  --i-representative-sequences ./dada2_rep_set.qza \
  --i-reference-database sepp-refs-gg-13-8.qza \
  --o-tree ./tree.qza \
  --o-placements ./tree_placements.qza \
  --p-threads 1  # update to a higher number if you can
#
# Alpha Rarefaction and Selecting a Rarefaction Depth
qiime diversity alpha-rarefaction \
  --i-table ./dada2_table.qza \
  --m-metadata-file ./metadata.tsv \
  --o-visualization ./alpha_rarefaction_curves.qzv \
  --p-min-depth 10 \
  --p-max-depth 4250
#
# Diversity analysis
qiime diversity core-metrics-phylogenetic \
  --i-table ./dada2_table.qza \
  --i-phylogeny ./tree.qza \
  --m-metadata-file ./metadata.tsv \
  --p-sampling-depth 2000 \
  --output-dir ./core-metrics-results
#
# Alpha diversity
qiime diversity alpha-group-significance \
  --i-alpha-diversity ./core-metrics-results/faith_pd_vector.qza \
  --m-metadata-file ./metadata.tsv \
  --o-visualization ./core-metrics-results/faiths_pd_statistics.qzv

qiime diversity alpha-group-significance \
 --i-alpha-diversity ./core-metrics-results/evenness_vector.qza \
 --m-metadata-file ./metadata.tsv \
 --o-visualization ./core-metrics-results/evenness_statistics.qzv

qiime longitudinal anova \
  --m-metadata-file ./core-metrics-results/faith_pd_vector.qza \
  --m-metadata-file ./metadata.tsv \
  --p-formula 'faith_pd ~ genotype * donor_status' \
  --o-visualization ./core-metrics-results/faiths_pd_anova.qzv

# Beta diversity
qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --m-metadata-column donor \
  --o-visualization core-metrics-results/unweighted-unifrac-donor-significance.qzv

qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/weighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --m-metadata-column donor \
  --o-visualization core-metrics-results/weighted-unifrac-donor-significance.qzv

qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --m-metadata-column cage_id \
  --o-visualization core-metrics-results/unweighted-unifrac-cage-significance.qzv \
  --p-pairwise

qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/weighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --m-metadata-column cage_id \
  --o-visualization core-metrics-results/weighted-unifrac-cage-significance.qzv \
  --p-pairwise

qiime diversity beta-group-significance \
  --i-distance-matrix core-metrics-results/weighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --m-metadata-column cage_id \
  --o-visualization core-metrics-results/weighted-unifrac-cage-significance_disp.qzv \
  --p-method permdisp
qiime diversity adonis \
  --i-distance-matrix core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file metadata.tsv \
  --o-visualization core-metrics-results/unweighted_adonis.qzv \
  --p-formula genotype+donor

# Taxonomic classification
wget \
  -O "gg-13-8-99-515-806-nb-classifier.qza" \
  "https://data.qiime2.org/2022.2/common/gg-13-8-99-515-806-nb-classifier.qza"
qiime feature-classifier classify-sklearn \
  --i-reads ./dada2_rep_set.qza \
  --i-classifier ./gg-13-8-99-515-806-nb-classifier.qza \
  --o-classification ./taxonomy.qza
qiime metadata tabulate \
  --m-input-file ./taxonomy.qza \
  --o-visualization ./taxonomy.qzv

qiime feature-table tabulate-seqs \
  --i-data ./dada2_rep_set.qza \
  --o-visualization ./dada2_rep_set.qzv

# Taxonomy barchart
qiime feature-table filter-samples \
  --i-table ./dada2_table.qza \
  --p-min-frequency 2000 \
  --o-filtered-table ./table_2k.qza

qiime taxa barplot \
  --i-table ./table_2k.qza \
  --i-taxonomy ./taxonomy.qza \
  --m-metadata-file ./metadata.tsv \
  --o-visualization ./taxa_barplot.qzv

# Differential abundance with ANCOM
qiime feature-table filter-features \
  --i-table ./table_2k.qza \
  --p-min-frequency 50 \
  --p-min-samples 4 \
  --o-filtered-table ./table_2k_abund.qza

qiime composition add-pseudocount \
  --i-table ./table_2k_abund.qza \
  --o-composition-table ./table2k_abund_comp.qza

qiime composition ancom \
  --i-table ./table2k_abund_comp.qza \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-column donor \
  --o-visualization ./ancom_donor.qzv

qiime composition ancom \
  --i-table ./table2k_abund_comp.qza \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-column genotype \
  --o-visualization ./ancom_genotype.qzv
# Taxonomic classification again
wget \
  -O "ref_seqs_v4.qza" \
  "https://data.qiime2.org/2022.2/tutorials/pd-mice/ref_seqs_v4.qza"

wget \
  -O "ref_tax.qza" \
  "https://data.qiime2.org/2022.2/tutorials/pd-mice/ref_tax.qza"
wget \
  -O "animal_distal_gut.qza" \
  "https://data.qiime2.org/2022.2/tutorials/pd-mice/animal_distal_gut.qza"
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads ./ref_seqs_v4.qza \
  --i-reference-taxonomy ./ref_tax.qza \
  --i-class-weight ./animal_distal_gut.qza \
  --o-classifier ./bespoke.qza
qiime feature-classifier classify-sklearn \
  --i-reads ./dada2_rep_set.qza \
  --i-classifier ./bespoke.qza \
  --o-classification ./bespoke_taxonomy.qza

qiime metadata tabulate \
  --m-input-file ./bespoke_taxonomy.qza \
  --o-visualization ./bespoke_taxonomy.qzv
qiime taxa collapse \
  --i-table ./table_2k.qza \
  --i-taxonomy ./taxonomy.qza \
  --o-collapsed-table ./uniform_table.qza \
  --p-level 7 # means that we group at species level

qiime feature-table filter-features \
  --i-table ./uniform_table.qza \
  --p-min-frequency 50 \
  --p-min-samples 4 \
  --o-filtered-table ./filtered_uniform_table.qza

qiime composition add-pseudocount \
  --i-table ./filtered_uniform_table.qza \
  --o-composition-table ./cfu_table.qza

qiime composition ancom \
  --i-table ./cfu_table.qza \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-column donor \
  --o-visualization ./ancom_donor_uniform.qzv
qiime taxa collapse \
  --i-table ./table_2k.qza \
  --i-taxonomy ./bespoke_taxonomy.qza \
  --p-level 7 \
  --o-collapsed-table ./bespoke_table.qza

qiime feature-table filter-features \
  --i-table ./bespoke_table.qza \
  --p-min-frequency 50 \
  --p-min-samples 4 \
  --o-filtered-table ./filtered_bespoke_table.qza

qiime composition add-pseudocount \
  --i-table ./filtered_bespoke_table.qza \
  --o-composition-table ./cfb_table.qza

qiime composition ancom \
  --i-table ./cfb_table.qza \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-column donor \
  --o-visualization ./ancom_donor_bespoke.qzv
# Longitudinal analysis
qiime longitudinal volatility \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-file ./core-metrics-results/unweighted_unifrac_pcoa_results.qza \
  --p-state-column days_post_transplant \
  --p-individual-id-column mouse_id \
  --p-default-group-column 'donor_status' \
  --p-default-metric 'Axis 2' \
  --o-visualization ./pc_vol.qzv

# Distance-based analysis
qiime longitudinal first-distances \
  --i-distance-matrix ./core-metrics-results/unweighted_unifrac_distance_matrix.qza \
  --m-metadata-file ./metadata.tsv \
  --p-state-column days_post_transplant \
  --p-individual-id-column mouse_id \
  --p-baseline 7 \
  --o-first-distances ./from_first_unifrac.qza

qiime longitudinal volatility \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-file ./from_first_unifrac.qza \
  --p-state-column days_post_transplant \
  --p-individual-id-column mouse_id \
  --p-default-metric Distance \
  --p-default-group-column 'donor_status' \
  --o-visualization ./from_first_unifrac_vol.qzv

qiime longitudinal linear-mixed-effects \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-file ./from_first_unifrac.qza \
  --p-metric Distance \
  --p-state-column days_post_transplant \
  --p-individual-id-column mouse_id \
  --p-group-columns genotype,donor \
  --o-visualization ./from_first_unifrac_lme.qzv

# Machine-learning classifiers for predicting sample characteristics
qiime sample-classifier classify-samples \
  --i-table ./dada2_table.qza \
  --m-metadata-file ./metadata.tsv \
  --m-metadata-column genotype_and_donor_status \
  --p-random-state 666 \
  --p-n-jobs 1 \
  --output-dir ./sample-classifier-results/

qiime sample-classifier heatmap \
  --i-table ./dada2_table.qza \
  --i-importance ./sample-classifier-results/feature_importance.qza \
  --m-sample-metadata-file ./metadata.tsv \
  --m-sample-metadata-column genotype_and_donor_status \
  --p-group-samples \
  --p-feature-count 100 \
  --o-heatmap ./sample-classifier-results/heatmap_100-features.qzv \
  --o-filtered-table ./sample-classifier-results/filtered-table_100-features.qza

