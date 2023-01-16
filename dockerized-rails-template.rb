# Table of contents:
#
# 1. Gems
# 2. Config
# 3. Docker
# 4. Binstubs
# 5. GitHub Actions
# 6. README
# 7. Initial setup

# 1. Gems
#-----------------------------------------------------------------------------------------------------------------------
gem "sidekiq"

gem_group :development, :test do
  gem "standard"
end

gem_group :development do
  gem "annotate"
  gem "chusaku", require: false
end

gem_group :test do
  gem "mocktail"
  gem "simplecov", require: false
end

run("sed -i '' '/^# gem \"redis\"/s/^# //' Gemfile")
run("sed '/webdrivers/d' Gemfile")
file("Gemfile.lock")

# 2. Config
#-----------------------------------------------------------------------------------------------------------------------
environment "config.active_job.queue_adapter = :sidekiq"

file(".rubocop.yml") do
  <<~RUBOCOP
    require: standard

    inherit_gem:
      standard: config/base.yml
  RUBOCOP
end

file("config/database.yml") do
  <<~CONFIG
    local: &local
      adapter: postgresql
      encoding: unicode
      host: db
      username: postgres
      password: password
      pool: 5

    development:
      <<: *local
      database: app_development

    test:
      <<: *local
      database: app_test

    production:
      adapter: postgresql
      encoding: unicode
      pool: 5
      url: <%= ENV["DATABASE_URL"] %>
  CONFIG
end

file("config/cable.yml") do
  <<~CONFIG
    development:
      adapter: redis
      url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>

    test:
      adapter: test

    production:
      adapter: redis
      url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
      channel_prefix: app_production
  CONFIG
end

file("config/initializers/generators.rb") do
  <<~CONFIG
    Rails.application.config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid, foreign_key_type: :uuid
    end
  CONFIG
end

file("Procfile.dev") do
  <<~PROCFILE
    web: bin/rails server -b 0.0.0.0 -p 3000
    worker: bundle exec sidekiq
  PROCFILE
end

file("test/application_system_test_case.rb") do
  <<~TESTCASE
    require "test_helper"

    class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
      driven_by \\
        :selenium,
        using: :headless_firefox,
        screen_size: [1400, 1400],
        options: {url: "http://selenium:4444", clear_local_storage: true, clear_session_storage: true}

      Capybara.enable_aria_label = true
    end
  TESTCASE
end

file("test/test_helper.rb") do
  <<~TESTHELPER
    require "simplecov"
    SimpleCov.start("rails") do
      add_filter("app/channels")
    end

    ENV["RAILS_ENV"] ||= "test"
    require_relative "../config/environment"
    require "rails/test_help"

    Capybara.server_host = "0.0.0.0"
    Capybara.app_host = "http://\#{ENV.fetch("HOSTNAME")}:\#{Capybara.server_port}"

    class ActiveSupport::TestCase
      # Run tests in parallel with specified workers
      parallelize(workers: :number_of_processors)

      # Get parallel tests to play nice with SimpleCov.
      parallelize_setup { |worker| SimpleCov.command_name("\#{SimpleCov.command_name}-\#{worker}") }
      parallelize_teardown { |worker| SimpleCov.result }

      # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
      fixtures :all

      # Resets state between tests.
      #
      # @return [void]
      def setup
        Mocktail.reset
        clear_enqueued_jobs if defined?(clear_enqueued_jobs)
      end
    end
  TESTHELPER
end


# 3. Docker
#-----------------------------------------------------------------------------------------------------------------------
file(".dockerignore") do
  <<~DOCKERIGNORE
    .git
    tmp
    !tmp/pids
    log
    public/assets
    public/packs
    .bundle

    db/*.sqlite3
    db/*.sqlite3-*

    storage
    config/master.key
    config/credentials/*.key

    node_modules
  DOCKERIGNORE
end

file("Dockerfile.dev") do
  <<~DOCKERFILE
    FROM ruby:3.1.2
    WORKDIR /app/

    # Install image dependencies.
    RUN apt-get update -qq && apt-get install -y postgresql-client vim
    RUN gem update --system

    # Install Ruby dependencies.
    COPY Gemfile /app/
    COPY Gemfile.lock /app/
    RUN bundle install

    # Define default command for the container.
    EXPOSE 3000
    CMD ["bin/dev"]
  DOCKERFILE
end

file("docker-compose.yml") do
  <<~DOCKERCOMPOSE
    version: "3.9"

    services:
      app:
        build:
          context: .
          dockerfile: ./Dockerfile.dev
        volumes:
          - .:/app
        tmpfs:
          - /app/tmp/pids
        ports:
          - 3000:3000
        environment:
          REDIS_URL: redis://redis:6379
          REDIS_PROVIDER: REDIS_URL
        depends_on:
          - db
          - redis
          - selenium

      db:
        image: postgres:latest
        ports:
          - 5432:5432
        environment:
          POSTGRES_PASSWORD: password

      redis:
        image: redis:latest
        ports:
          - 6379:6379

      selenium:
        image: seleniarm/standalone-firefox
        volumes:
          - .:/app
  DOCKERCOMPOSE
end

# 4. Binstubs
#-----------------------------------------------------------------------------------------------------------------------
file("bin/compose") do
  <<~BIN
    #!/usr/bin/env bash

    docker-compose up $*
  BIN
end
run("chmod +x bin/compose")

file("bin/credentials") do
  <<~BIN
    #!/usr/bin/env bash

    docker-compose run --no-deps --rm -e "EDITOR=vim" app bin/rails credentials:edit
  BIN
end
run("chmod +x bin/credentials")

file("bin/dev") do
  <<~BIN
    #!/usr/bin/env bash

    if ! gem list foreman -i --silent; then
      echo "Installing foreman..."
      gem install foreman
    fi

    foreman start -f Procfile.dev "$@"
  BIN
end
run("chmod +x bin/dev")

file("bin/run") do
  <<~BIN
    #!/usr/bin/env bash

    docker-compose run --no-deps --rm app $*
  BIN
end
run("chmod +x bin/run")

# 5. GitHub Actions
#-----------------------------------------------------------------------------------------------------------------------
file(".github/workflows/docker-ci.yml") do
  <<~CI
    name: Linting, annotations, and test suite
    on: [pull_request]
    env:
      RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
    jobs:
      run:
        runs-on: ubuntu-latest
        steps:
          - name: Check out repository code
            uses: actions/checkout@v3

          - name: Build with Docker Compose
            run: docker-compose build

          - name: Start Postgres database
            run: docker-compose up --detach db

          - name: Create database
            run: docker-compose run -e RAILS_MASTER_KEY --rm app bin/rails db:create

          - name: Load schema
            run: docker-compose run -e RAILS_MASTER_KEY --rm app bin/rails db:schema:load

          - name: Run Standard
            run: bin/run bundle exec standardrb

          - name: Run Annotate
            run: bin/run bundle exec annotate --frozen

          - name: Run Chusaku
            run: bin/run bundle exec chusaku --dry-run --exit-with-error-on-annotation

          - name: Run tests
            run: docker-compose run -e RAILS_MASTER_KEY --rm app bin/rails test

          - name: Run system tests
            run: docker-compose run -e RAILS_MASTER_KEY --rm app bin/rails test:system
  CI
end

# 6. README
#-----------------------------------------------------------------------------------------------------------------------
file("README.md") do
  <<~README
    ## Local development

    Make sure you have Docker Compose installed and grab a copy of the master key before proceeding.

    ### First-time setup

    When booting up a local copy of the app for the first time:

    1. Run `bin/compose` to boot up Docker Compose and build Docker images.
    2. Run `bin/run bin/rails db:create` to create development and test databases.
    3. Run `bin/run bin/rails db:schema:load` to load in the current schema.
    4. Run `bin/run bin/rails db:seed` to seed the database.

    ### General commands

    ```bash
    $ bin/compose           # Boot up all Docker Compose services
    $ bin/compose --build   # Build/rebuild all services
    $ bin/run               # Run a command in the app service
                            # e.g. bin/run bin/rails test
                            #      bin/run bundle exec chusaku
    $ bin/credentials       # Edit encrypted credentials with Vim
    ```

    ### Linting and annotations

    ```bash
    $ bin/run bundle exec annotate     # Annotates models
    $ bin/run bundle exec chusaku      # Annotates controllers
    $ bin/run bundle exec standardrb   # Runs style checks
    ```
  README
end

# 7. Initial setup
#-----------------------------------------------------------------------------------------------------------------------
run("bin/compose --build --detach")
run("bin/run bin/rails importmap:install")
run("bin/run bin/rails turbo:install")
run("bin/run bin/rails turbo:install:redis")
run("bin/run bin/rails stimulus:install")
run("bin/run bin/rails db:create")
run("bin/run bin/rails db:migrate")
run("bin/run bin/rails g annotate:install")
run("bin/run bundle exec standardrb --fix")
run("docker-compose stop")
