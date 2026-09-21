R ?= Rscript

.PHONY: all tables figures validate

all: tables figures validate

tables:
	$(R) analysis/build_tables.R results/aggregate results/tables

figures:
	$(R) analysis/build_figures.R results/aggregate results/figures

validate:
	$(R) analysis/validate_repository.R
