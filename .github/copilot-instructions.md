# ChronoModel - Temporal Database System

ChronoModel is a Ruby gem that implements temporal database functionality for PostgreSQL using updatable views, table inheritance, and INSTEAD OF triggers. It provides "time machine" features for ActiveRecord models, allowing querying of data as it existed at any point in time.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Setup
- Install PostgreSQL and ensure it's running: `sudo service postgresql start`
- Create PostgreSQL superuser: `sudo -u postgres createuser -s runner`
- Set password for database user: `sudo -u postgres psql -c "ALTER USER runner WITH PASSWORD 'test123';"`
- Install bundler for user: `gem install bundler --user-install`
- Add bundler to PATH: `export PATH="/home/runner/.local/share/gem/ruby/3.2.0/bin:$PATH"`

### Build and Test Process
- Install dependencies: `bundle config set --local path 'vendor/bundle' && bundle install` -- takes 60-90 seconds. NEVER CANCEL.
- Set up databases:
  - `createdb chronomodel`
  - `createdb chronomodel_railsapp`
  - `psql -d chronomodel -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"`
  - `psql -d chronomodel_railsapp -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"`
- Create test config: Create `spec/config.yml` with database connection details (see example below)
- Run linting: `bundle exec rubocop` -- takes 5-10 seconds. Clean codebase with 0 offenses.
- Run core tests: `BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle exec rspec spec/chrono_model` -- takes 12-15 seconds. NEVER CANCEL.
- Run full test suite: `BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle exec rspec` -- takes 3-4 minutes. NEVER CANCEL. Set timeout to 300+ seconds.

### Database Configuration Example (spec/config.yml)
```yaml
adapter: chronomodel
host: 127.0.0.1
username: runner
password: "test123"
database: chronomodel
pool: 11
```

### Testing Multiple Rails Versions
- Use Appraisal gemfiles: `BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile` (available: rails_7.0, rails_7.1, rails_7.2, rails_8.0, rails_edge)
- Rails 7.2 is the most stable for testing
- Rails 8.0 may have compatibility issues in current development

## Validation Scenarios

Always test the complete temporal functionality after making changes:

### Test Scenario: Temporal Table Creation and Time Machine
1. Connect to database using chronomodel adapter
2. Create a temporal table: `create_table :countries, temporal: true do |t|`
3. Create model with TimeMachine: `class Country < ActiveRecord::Base; include ChronoModel::TimeMachine; end`
4. Test CRUD operations: Create, update records
5. Test time machine: `Country.as_of(past_time).find(id)` vs `Country.find(id)`
6. Verify history tracking: `Country::History.where(id: record_id).count`
7. Test temporal queries: `Country.as_of(time).all`

### Expected Results
- Temporal tables create views in public schema, tables in temporal schema, history in history schema
- Time machine queries return data as it existed at specific points in time
- History tables automatically track all changes with validity ranges
- Core tests: 468 examples, 0 failures
- Full test suite: 488 examples (19 failures in Aruba integration tests - this is expected)

## Common Development Tasks

### Running Tests
- Core ChronoModel tests only: `bundle exec rspec spec/chrono_model`
- Full test suite including Rails integration: `bundle exec rspec`
- Specific Rails version: `BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile bundle exec rspec`

### Code Quality
- Linting: `bundle exec rubocop` - should show "0 offenses detected"
- Format code: `bundle exec rubocop -a` (auto-fix issues)

### Database Operations
- Connect to test database: `PGPASSWORD=test123 psql -h 127.0.0.1 -U runner -d chronomodel`
- Check extensions: `PGPASSWORD=test123 psql -d chronomodel -c "\\dx"`
- Recreate test database: `dropdb chronomodel && createdb chronomodel && psql -d chronomodel -c "CREATE EXTENSION btree_gist;"`

### Creating Test Rails App
- Generate test app: `bundle exec rake testapp:create` -- takes 5-10 minutes. NEVER CANCEL. Set timeout to 600+ seconds.
- Configure database.yml for chronomodel adapter
- Set schema format: `config.active_record.schema_format = :sql` in application.rb

## Key Project Structure

### Repository Layout
```
├── lib/chrono_model/          # Main gem code
│   ├── adapter.rb            # PostgreSQL adapter with temporal extensions
│   ├── time_machine.rb       # Time machine module for models
│   └── adapter/              # Adapter modules (migrations, DDL, indexes)
├── spec/                     # Test suite
│   ├── chrono_model/         # Core functionality tests
│   ├── aruba/               # Rails integration tests
│   └── fixtures/            # Test fixtures and configurations
├── gemfiles/                # Appraisal gemfiles for Rails versions
├── sql/                     # SQL extensions and examples
├── README.md                # Main documentation
├── README.sql              # SQL example implementation
└── CONTRIBUTING.md         # Development guidelines
```

### Important Files
- `lib/chrono_model/adapter.rb` - Core database adapter extending PostgreSQL
- `lib/chrono_model/time_machine.rb` - Time machine functionality for models
- `spec/support/connection.rb` - Test database connection management
- `Appraisals` - Rails version matrix for testing
- `.rubocop.yml` - Code style configuration

## Build and Test Timing Expectations

### CRITICAL: Timeout Guidelines
- **NEVER CANCEL** long-running commands. Builds and tests can take several minutes.
- Bundle install: 60-90 seconds timeout minimum
- Core tests: 15-30 seconds timeout minimum  
- Full test suite: 300-600 seconds timeout minimum
- Test app creation: 600+ seconds timeout minimum

### Expected Durations
- `bundle install`: ~60 seconds
- `bundle exec rubocop`: ~10 seconds
- Core tests (`rspec spec/chrono_model`): ~12 seconds
- Full test suite (`rspec`): ~180 seconds
- Test Rails app creation: ~300 seconds (if successful)

## Common Issues and Solutions

### Database Connection Issues
- Ensure PostgreSQL is running: `sudo service postgresql start`
- Check user permissions: User must be superuser to create/manage extensions
- Verify btree_gist extension: Required for temporal indexes
- Use 127.0.0.1 instead of localhost to avoid IPv6 issues

### Test Failures
- Core tests should pass completely (468/468)
- Aruba integration tests may fail (19 failures expected) - these test Rails integration
- If core tests fail, check database configuration and permissions

### Rails Version Compatibility
- Use Rails 7.2 for stable testing: `BUNDLE_GEMFILE=gemfiles/rails_7.2.gemfile`
- Rails 8.0 may have adapter compatibility issues in development
- All supported versions defined in `.github/workflows/ruby.yml`

## Requirements
- Ruby >= 3.0 (tested with 3.2.3)
- PostgreSQL >= 9.4 (tested with 16.x) 
- ActiveRecord >= 7.0 (supports 7.0, 7.1, 7.2, 8.0)
- btree_gist PostgreSQL extension (required for temporal indexes)

## Additional Notes
- Schema format must be `:sql` (not `:ruby`) due to database-specific features
- All timestamps stored as UTC regardless of timezone settings
- Temporal tables use exclusion constraints to prevent overlapping history
- Foreign keys are not fully supported (see issue #174)
- Counter cache columns should use `no_journal` option to avoid race conditions