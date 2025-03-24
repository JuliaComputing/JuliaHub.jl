JULIA:=julia

help:
	@echo "The following make commands are available:"
	@echo " - make docs: build the documentation"
	@echo " - make docs-environment: instantiate the docs environment"
	@echo " - make test: run the tests"

docs/Manifest.toml: docs/Project.toml
	@echo "Instantiating the docs/ environment:"
	${JULIA} --color=yes --project=docs/ -e 'using Pkg; Pkg.instantiate()'

docs-manifest:
	rm -f docs/Manifest.toml
	$(MAKE) docs/Manifest.toml

docs: docs/Manifest.toml
	${JULIA} --project=docs/ docs/make.jl

fix-doctests: docs/Manifest.toml
	${JULIA} --project=docs/ docs/make.jl --fix-doctests

changelog:
	${JULIA} --project=docs/ docs/changelog.jl

test:
	${JULIA} --project -e 'using Pkg; Pkg.test()'

.PHONY: default docs-manifest docs test
