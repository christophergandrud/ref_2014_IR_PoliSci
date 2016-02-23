# ---------------------------------------------------------------------------- #
# Create data set for examining IR/Poli Sci/REF and journal metrics
# Christopher Gandrud
# MIT License
# ---------------------------------------------------------------------------- #

# Load required packages
library(repmis)
library(dplyr)
library(rio)
library(tidyr)
library(DataCombine)

# Set working directory
possibles <- c('/git_repositories/ref_2014_IR_PoliSci/')
set_valid_wd(possibles)

# All submissions ----------
all_submissions <- import('data/raw/Output-Table 1.csv')

# Only journals
journals <- all_submissions %>% filter(OutputType == 'D') %>%
    select(UKPRN, VolumeTitle)

school_codes <- import('data/raw/Institution-Table 1.csv') %>%
    select(UKPRN, Name) %>%
    rename(school = Name)

comb_journals <- merge(school_codes, journals, by = 'UKPRN', all.y = T) %>%
    rename(journal = VolumeTitle)

# Clean up journal titles to enable merging
comb_journals$journal <- as.character(comb_journals$journal) %>% tolower
comb_journals$journal <- gsub('^the ', '', comb_journals$journal)
comb_journals$journal <- gsub('&', 'and', comb_journals$journal)

comb_journals$journal[grep('^jcms', comb_journals$journal)] <- 'jcms'
comb_journals$journal[grep('^millennium', comb_journals$journal)] <- 'millennium'

comb_journals <- comb_journals %>% arrange(school, journal)

# Journal impact factors -------------
impact <- import('data/raw/Impact Factor.xlsx')
impact <- impact[, c(1, 3, 5)]
names(impact) <- c('journal', 'impact_factor', 'google_top')
impact$journal <- impact$journal %>% tolower

# Clean up journal titles to enable merging
impact$journal[impact$journal == 'governance-an international journal of policy administration and institutions'] <- 'governance'
impact$journal[grep('^jcms', impact$journal)] <- 'jcms'
impact$journal[grep('^millennium', impact$journal)] <- 'millennium'

# Create dummy for whether or not journal is in the Google IR and Political Science top 20
impact$google_top[!is.na(impact$google_top)] <- 1
impact$google_top[is.na(impact$google_top)] <- 0

comb <- left_join(comb_journals, impact, by = 'journal')

comb$google_top[is.na(comb$google_top)] <- 0

comb$google_plus <- comb$google_top
comb$google_plus[comb$journal == 'review of international political economy'] <- 1
comb$google_plus[comb$journal == 'new political economy'] <- 1

# Create counter for total submissions
comb$fake <- 1
number_subs <- comb %>% group_by(school) %>% summarise(total_subs = sum(fake))

total_impact <- comb %>% group_by(school) %>%
    summarise(total_impact = sum(impact_factor, na.rm = T))

school_level <- inner_join(total_impact, number_subs, by = 'school')

school_level$mean_impact <- school_level$total_impact / school_level$total_subs

school_level <- right_join(school_codes, school_level, by = 'school')

# REF scores ----------------
ref_scores <- import('data/raw/REF2014 Results.xlsx', skip = 6) %>%
    filter(`Unit of assessment number` == 21)

ref_scores <- ref_scores[, c(1, 10, 12, 13, 14, 15)]
names(ref_scores) <- c('UKPRN', 'category', 'perc_4_star', 'perc_3_star',
                       'perc_2_star', 'perc_1_star')

# Create REF GPA
ref_scores$ref_gpa <- (ref_scores$perc_4_star * 4 +
                           ref_scores$perc_3_star * 3 +
                           ref_scores$perc_2_star * 2 +
                           ref_scores$perc_1_star * 1) / 100

comb_scores <- inner_join(school_level, ref_scores, by = 'UKPRN')

# Mean Impact vs. REF
outputs <- comb_scores %>% filter(category == 'Outputs')

# Create variable to highlight specific schools graphically
outputs$school_label <- 'Other'
outputs$school_label[outputs$UKPRN == 10001478] <- 'City'
outputs$school_label[outputs$UKPRN == 10004063] <- 'LSE'
outputs$school_label[outputs$UKPRN == 10007774] <- 'Oxford'
outputs$school_label[outputs$UKPRN == 10007791] <- 'Essex'

outputs$highlight <- 0
outputs$highlight[outputs$school_label != 'Other'] <- 1
outputs$highlight <- outputs$highlight %>% as.factor

outputs$school_label <- outputs$school_label %>% as.factor

# Google top 40
google_40 <- comb %>% group_by(UKPRN) %>%
    summarize(google_40_perc = (sum(google_top) / sum(fake)) * 100)

google_40_plus <- comb %>% group_by(UKPRN) %>%
    summarize(google_40_plus = (sum(google_plus) / sum(fake)) * 100)

comb_google <- inner_join(google_40, google_40_plus, by = 'UKPRN')
comb_google <- inner_join(comb_google, ref_scores, by = 'UKPRN')

comb_google <- comb_google %>% filter(category == 'Outputs')

comb_google$school_label <- 'Other'
comb_google$school_label[comb_google$UKPRN == 10001478] <- 'City'
comb_google$school_label[comb_google$UKPRN == 10004063] <- 'LSE'
comb_google$school_label[comb_google$UKPRN == 10007774] <- 'Oxford'
comb_google$school_label[comb_google$UKPRN == 10007791] <- 'Essex'

comb_google$highlight <- 0
comb_google$highlight[comb_google$school_label != 'Other'] <- 1
comb_google$highlight <- comb_google$highlight %>% as.factor

comb_out <- merge(outputs[, c('UKPRN', 'school', 'mean_impact')],
                  comb_google[, c('UKPRN', 'google_40_perc', 'google_40_plus',
                                  'ref_gpa')],
                  by = 'UKPRN')
export(comb_out, 'data/gpa_impact_google.csv')
