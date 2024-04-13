.PHONY: install serve

install:
	@bundle config set --local path vendor/bundle
	@bundle install

serve:
	@bundle exec jekyll serve --livereload
