# Dockerized Rails Template

This is a [Rails application template](https://guides.rubyonrails.org/rails_application_templates.html) for an opinionated Docker setup.

- Docker Compose-optimized project
  - App, Postgres, Redis, and Selenium services
  - Sidekiq worker runs via Foreman to prevent `bin/dev` or `Procfile.dev` clashes with gems you might add later
- Binstubs that make working with Docker Compose easy
  - `bin/compose`: Alias for `docker-compose up`
  - `bin/run`: Runs a command in the `app` service
  - `bin/credentials`: Opens the encrypted credentials file in Vim
- Additional default gems
  - [annotate](https://github.com/ctran/annotate_models): Model annotations
  - [chusaku](https://github.com/nshki/chusaku): Controller annotations
  - [mocktail](https://github.com/testdouble/mocktail): Easier mocking in tests
  - [sidekiq](https://github.com/mperham/sidekiq): Background processing
  - [simplecov](https://github.com/simplecov-ruby/simplecov): Test suite code coverage
  - [standard](https://github.com/testdouble/standard): Style guide, linter, and fixer
- GitHub Action workflow that runs linting, annotations, and test suite

## Setup

```
$ rails new my_new_project --template=https://raw.githubusercontent.com/nshki/dockerized-rails/main/dockerized-rails-template.rb --database=postgresql --skip-bundle
```
