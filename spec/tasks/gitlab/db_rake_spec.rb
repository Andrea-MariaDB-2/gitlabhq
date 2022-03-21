# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'gitlab:db namespace rake task', :silence_stdout do
  before :all do
    Rake.application.rake_require 'active_record/railties/databases'
    Rake.application.rake_require 'tasks/seed_fu'
    Rake.application.rake_require 'tasks/gitlab/db'

    # empty task as env is already loaded
    Rake::Task.define_task :environment
  end

  before do
    # Stub out db tasks
    allow(Rake::Task['db:migrate']).to receive(:invoke).and_return(true)
    allow(Rake::Task['db:structure:load']).to receive(:invoke).and_return(true)
    allow(Rake::Task['db:seed_fu']).to receive(:invoke).and_return(true)
  end

  describe 'clear_all_connections' do
    it 'calls clear_all_connections!' do
      expect(ActiveRecord::Base).to receive(:clear_all_connections!)

      run_rake_task('gitlab:db:clear_all_connections')
    end
  end

  describe 'mark_migration_complete' do
    context 'with a single database' do
      let(:main_model) { ActiveRecord::Base }

      before do
        skip_if_multiple_databases_are_setup
      end

      it 'marks the migration complete on the given database' do
        expect(main_model.connection).to receive(:quote).and_call_original
        expect(main_model.connection).to receive(:execute)
          .with("INSERT INTO schema_migrations (version) VALUES ('123')")

        run_rake_task('gitlab:db:mark_migration_complete', '[123]')
      end
    end

    context 'with multiple databases' do
      let(:main_model) { double(:model, connection: double(:connection)) }
      let(:ci_model) { double(:model, connection: double(:connection)) }
      let(:base_models) { { 'main' => main_model, 'ci' => ci_model } }

      before do
        skip_if_multiple_databases_not_setup

        allow(Gitlab::Database).to receive(:database_base_models).and_return(base_models)
      end

      it 'marks the migration complete on each database' do
        expect(main_model.connection).to receive(:quote).with('123').and_return("'123'")
        expect(main_model.connection).to receive(:execute)
          .with("INSERT INTO schema_migrations (version) VALUES ('123')")

        expect(ci_model.connection).to receive(:quote).with('123').and_return("'123'")
        expect(ci_model.connection).to receive(:execute)
          .with("INSERT INTO schema_migrations (version) VALUES ('123')")

        run_rake_task('gitlab:db:mark_migration_complete', '[123]')
      end

      context 'when the single database task is used' do
        it 'marks the migration complete for the given database' do
          expect(main_model.connection).to receive(:quote).with('123').and_return("'123'")
          expect(main_model.connection).to receive(:execute)
            .with("INSERT INTO schema_migrations (version) VALUES ('123')")

          expect(ci_model.connection).not_to receive(:quote)
          expect(ci_model.connection).not_to receive(:execute)

          run_rake_task('gitlab:db:mark_migration_complete:main', '[123]')
        end
      end

      context 'with geo configured' do
        before do
          skip_unless_geo_configured
        end

        it 'does not create a task for the geo database' do
          expect { run_rake_task('gitlab:db:mark_migration_complete:geo') }
            .to raise_error(/Don't know how to build task 'gitlab:db:mark_migration_complete:geo'/)
        end
      end
    end

    context 'when the migration is already marked complete' do
      let(:main_model) { double(:model, connection: double(:connection)) }
      let(:base_models) { { 'main' => main_model } }

      before do
        allow(Gitlab::Database).to receive(:database_base_models).and_return(base_models)
      end

      it 'prints a warning message' do
        allow(main_model.connection).to receive(:quote).with('123').and_return("'123'")

        expect(main_model.connection).to receive(:execute)
          .with("INSERT INTO schema_migrations (version) VALUES ('123')")
          .and_raise(ActiveRecord::RecordNotUnique)

        expect { run_rake_task('gitlab:db:mark_migration_complete', '[123]') }
          .to output(/Migration version '123' is already marked complete on database main/).to_stdout
      end
    end

    context 'when an invalid version is given' do
      let(:main_model) { double(:model, connection: double(:connection)) }
      let(:base_models) { { 'main' => main_model } }

      before do
        allow(Gitlab::Database).to receive(:database_base_models).and_return(base_models)
      end

      it 'prints an error and exits' do
        expect(main_model).not_to receive(:quote)
        expect(main_model.connection).not_to receive(:execute)

        expect { run_rake_task('gitlab:db:mark_migration_complete', '[abc]') }
          .to output(/Must give a version argument that is a non-zero integer/).to_stdout
          .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  describe 'configure' do
    it 'invokes db:migrate when schema has already been loaded' do
      allow(ActiveRecord::Base.connection).to receive(:tables).and_return(%w[table1 table2])
      expect(Rake::Task['db:migrate']).to receive(:invoke)
      expect(Rake::Task['db:structure:load']).not_to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
    end

    it 'invokes db:shema:load and db:seed_fu when schema is not loaded' do
      allow(ActiveRecord::Base.connection).to receive(:tables).and_return([])
      expect(Rake::Task['db:structure:load']).to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).to receive(:invoke)
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
    end

    it 'invokes db:shema:load and db:seed_fu when there is only a single table present' do
      allow(ActiveRecord::Base.connection).to receive(:tables).and_return(['default'])
      expect(Rake::Task['db:structure:load']).to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).to receive(:invoke)
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
    end

    it 'does not invoke any other rake tasks during an error' do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(RuntimeError, 'error')
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect(Rake::Task['db:structure:load']).not_to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.to raise_error(RuntimeError, 'error')
      # unstub connection so that the database cleaner still works
      allow(ActiveRecord::Base).to receive(:connection).and_call_original
    end

    it 'does not invoke seed after a failed schema_load' do
      allow(ActiveRecord::Base.connection).to receive(:tables).and_return([])
      allow(Rake::Task['db:structure:load']).to receive(:invoke).and_raise(RuntimeError, 'error')
      expect(Rake::Task['db:structure:load']).to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.to raise_error(RuntimeError, 'error')
    end

    context 'SKIP_POST_DEPLOYMENT_MIGRATIONS environment variable set' do
      let(:rails_paths) { { 'db' => ['db'], 'db/migrate' => ['db/migrate'] } }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SKIP_POST_DEPLOYMENT_MIGRATIONS').and_return true

        # Our environment has already been loaded, so we need to pretend like post_migrations were not
        allow(Rails.application.config).to receive(:paths).and_return(rails_paths)
        allow(ActiveRecord::Migrator).to receive(:migrations_paths).and_return(rails_paths['db/migrate'].dup)
      end

      it 'adds post deployment migrations before schema load if the schema is not already loaded' do
        allow(ActiveRecord::Base.connection).to receive(:tables).and_return([])
        expect(Gitlab::Database).to receive(:add_post_migrate_path_to_rails).and_call_original
        expect(Rake::Task['db:structure:load']).to receive(:invoke)
        expect(Rake::Task['db:seed_fu']).to receive(:invoke)
        expect(Rake::Task['db:migrate']).not_to receive(:invoke)
        expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
        expect(rails_paths['db/migrate'].include?(File.join(Rails.root, 'db', 'post_migrate'))).to be(true)
      end

      it 'ignores post deployment migrations  when schema has already been loaded' do
        allow(ActiveRecord::Base.connection).to receive(:tables).and_return(%w[table1 table2])
        expect(Rake::Task['db:migrate']).to receive(:invoke)
        expect(Gitlab::Database).not_to receive(:add_post_migrate_path_to_rails)
        expect(Rake::Task['db:structure:load']).not_to receive(:invoke)
        expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
        expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
        expect(rails_paths['db/migrate'].include?(File.join(Rails.root, 'db', 'post_migrate'))).to be(false)
      end
    end
  end

  describe 'unattended' do
    using RSpec::Parameterized::TableSyntax

    where(:schema_migration_table_exists, :needs_migrations, :rake_output) do
      false | false | "unattended_migrations_completed"
      false | true | "unattended_migrations_completed"
      true | false | "unattended_migrations_static"
      true | true | "unattended_migrations_completed"
    end

    before do
      allow(Rake::Task['gitlab:db:configure']).to receive(:invoke).and_return(true)
    end

    with_them do
      it 'outputs changed message for automation after operations happen' do
        allow(ActiveRecord::Base.connection.schema_migration).to receive(:table_exists?).and_return(schema_migration_table_exists)
        allow_any_instance_of(ActiveRecord::MigrationContext).to receive(:needs_migration?).and_return(needs_migrations)
        expect { run_rake_task('gitlab:db:unattended') }. to output(/^#{rake_output}$/).to_stdout
      end
    end
  end

  describe 'clean_structure_sql' do
    let_it_be(:clean_rake_task) { 'gitlab:db:clean_structure_sql' }
    let_it_be(:test_task_name) { 'gitlab:db:_test_multiple_structure_cleans' }
    let_it_be(:input) { 'this is structure data' }

    let(:output) { StringIO.new }

    before do
      structure_files = %w[structure.sql ci_structure.sql]

      allow(File).to receive(:open).and_call_original

      structure_files.each do |structure_file_name|
        structure_file = File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, structure_file_name)
        stub_file_read(structure_file, content: input)
        allow(File).to receive(:open).with(structure_file.to_s, any_args).and_yield(output)
      end

      if Gitlab.ee?
        allow(File).to receive(:open).with(Rails.root.join(Gitlab::Database::GEO_DATABASE_DIR, 'structure.sql').to_s, any_args).and_yield(output)
      end
    end

    after do
      Rake::Task[test_task_name].clear if Rake::Task.task_defined?(test_task_name)
    end

    it 'can be executed multiple times within another rake task' do
      expect_multiple_executions_of_task(test_task_name, clean_rake_task, count: 2) do
        database_count = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).size

        expect_next_instances_of(Gitlab::Database::SchemaCleaner, database_count) do |cleaner|
          expect(cleaner).to receive(:clean).with(output)
        end
      end
    end
  end

  describe 'drop_tables' do
    let(:tables) { %w(one two schema_migrations) }
    let(:views) { %w(three four) }
    let(:schemas) { Gitlab::Database::EXTRA_SCHEMAS }

    context 'with a single database' do
      let(:connection) { ActiveRecord::Base.connection }

      before do
        skip_if_multiple_databases_are_setup

        allow(connection).to receive(:execute).and_return(nil)

        allow(connection).to receive(:tables).and_return(tables)
        allow(connection).to receive(:views).and_return(views)
      end

      it 'drops all objects for the database', :aggregate_failures do
        expect_objects_to_be_dropped(connection)

        run_rake_task('gitlab:db:drop_tables')
      end
    end

    context 'with multiple databases', :aggregate_failures do
      let(:main_model) { double(:model, connection: double(:connection, tables: tables, views: views)) }
      let(:ci_model) { double(:model, connection: double(:connection, tables: tables, views: views)) }
      let(:base_models) { { 'main' => main_model, 'ci' => ci_model } }

      before do
        skip_if_multiple_databases_not_setup

        allow(Gitlab::Database).to receive(:database_base_models).and_return(base_models)

        allow(main_model.connection).to receive(:table_exists?).with('schema_migrations').and_return(true)
        allow(ci_model.connection).to receive(:table_exists?).with('schema_migrations').and_return(true)

        (tables + views + schemas).each do |name|
          allow(main_model.connection).to receive(:quote_table_name).with(name).and_return("\"#{name}\"")
          allow(ci_model.connection).to receive(:quote_table_name).with(name).and_return("\"#{name}\"")
        end
      end

      it 'drops all objects for all databases', :aggregate_failures do
        expect_objects_to_be_dropped(main_model.connection)
        expect_objects_to_be_dropped(ci_model.connection)

        run_rake_task('gitlab:db:drop_tables')
      end

      context 'when the single database task is used' do
        it 'drops all objects for the given database', :aggregate_failures do
          expect_objects_to_be_dropped(main_model.connection)

          expect(ci_model.connection).not_to receive(:execute)

          run_rake_task('gitlab:db:drop_tables:main')
        end
      end

      context 'with geo configured' do
        before do
          skip_unless_geo_configured
        end

        it 'does not create a task for the geo database' do
          expect { run_rake_task('gitlab:db:drop_tables:geo') }
            .to raise_error(/Don't know how to build task 'gitlab:db:drop_tables:geo'/)
        end
      end
    end

    def expect_objects_to_be_dropped(connection)
      expect(connection).to receive(:execute).with('DROP TABLE IF EXISTS "one" CASCADE')
      expect(connection).to receive(:execute).with('DROP TABLE IF EXISTS "two" CASCADE')

      expect(connection).to receive(:execute).with('DROP VIEW IF EXISTS "three" CASCADE')
      expect(connection).to receive(:execute).with('DROP VIEW IF EXISTS "four" CASCADE')

      expect(connection).to receive(:execute).with('TRUNCATE schema_migrations')

      Gitlab::Database::EXTRA_SCHEMAS.each do |schema|
        expect(connection).to receive(:execute).with("DROP SCHEMA IF EXISTS \"#{schema}\" CASCADE")
      end
    end
  end

  describe 'create_dynamic_partitions' do
    context 'with a single database' do
      before do
        skip_if_multiple_databases_are_setup
      end

      it 'delegates syncing of partitions without limiting databases' do
        expect(Gitlab::Database::Partitioning).to receive(:sync_partitions)

        run_rake_task('gitlab:db:create_dynamic_partitions')
      end
    end

    context 'with multiple databases' do
      before do
        skip_if_multiple_databases_not_setup
      end

      context 'when running the multi-database variant' do
        it 'delegates syncing of partitions without limiting databases' do
          expect(Gitlab::Database::Partitioning).to receive(:sync_partitions)

          run_rake_task('gitlab:db:create_dynamic_partitions')
        end
      end

      context 'when running a single-database variant' do
        it 'delegates syncing of partitions for the chosen database' do
          expect(Gitlab::Database::Partitioning).to receive(:sync_partitions).with(only_on: 'main')

          run_rake_task('gitlab:db:create_dynamic_partitions:main')
        end
      end
    end

    context 'with geo configured' do
      before do
        skip_unless_geo_configured
      end

      it 'does not create a task for the geo database' do
        expect { run_rake_task('gitlab:db:create_dynamic_partitions:geo') }
          .to raise_error(/Don't know how to build task 'gitlab:db:create_dynamic_partitions:geo'/)
      end
    end
  end

  describe 'reindex' do
    context 'with a single database' do
      before do
        skip_if_multiple_databases_are_setup
      end

      it 'delegates to Gitlab::Database::Reindexing' do
        expect(Gitlab::Database::Reindexing).to receive(:invoke).with(no_args)

        run_rake_task('gitlab:db:reindex')
      end

      context 'when reindexing is not enabled' do
        it 'is a no-op' do
          expect(Gitlab::Database::Reindexing).to receive(:enabled?).and_return(false)
          expect(Gitlab::Database::Reindexing).not_to receive(:invoke)

          expect { run_rake_task('gitlab:db:reindex') }.to raise_error(SystemExit)
        end
      end
    end

    context 'with multiple databases' do
      let(:base_models) { { 'main' => double(:model), 'ci' => double(:model) } }

      before do
        skip_if_multiple_databases_not_setup

        allow(Gitlab::Database).to receive(:database_base_models).and_return(base_models)
      end

      it 'delegates to Gitlab::Database::Reindexing without a specific database' do
        expect(Gitlab::Database::Reindexing).to receive(:invoke).with(no_args)

        run_rake_task('gitlab:db:reindex')
      end

      context 'when the single database task is used' do
        it 'delegates to Gitlab::Database::Reindexing with a specific database' do
          expect(Gitlab::Database::Reindexing).to receive(:invoke).with('ci')

          run_rake_task('gitlab:db:reindex:ci')
        end

        context 'when reindexing is not enabled' do
          it 'is a no-op' do
            expect(Gitlab::Database::Reindexing).to receive(:enabled?).and_return(false)
            expect(Gitlab::Database::Reindexing).not_to receive(:invoke)

            expect { run_rake_task('gitlab:db:reindex:ci') }.to raise_error(SystemExit)
          end
        end
      end

      context 'with geo configured' do
        before do
          skip_unless_geo_configured
        end

        it 'does not create a task for the geo database' do
          expect { run_rake_task('gitlab:db:reindex:geo') }
            .to raise_error(/Don't know how to build task 'gitlab:db:reindex:geo'/)
        end
      end
    end
  end

  describe 'enqueue_reindexing_action' do
    let(:index_name) { 'public.users_pkey' }

    it 'creates an entry in the queue' do
      expect do
        run_rake_task('gitlab:db:enqueue_reindexing_action', "[#{index_name}, main]")
      end.to change { Gitlab::Database::PostgresIndex.find(index_name).queued_reindexing_actions.size }.from(0).to(1)
    end

    it 'defaults to main database' do
      expect(Gitlab::Database::SharedModel).to receive(:using_connection).with(ActiveRecord::Base.connection).and_call_original

      expect do
        run_rake_task('gitlab:db:enqueue_reindexing_action', "[#{index_name}]")
      end.to change { Gitlab::Database::PostgresIndex.find(index_name).queued_reindexing_actions.size }.from(0).to(1)
    end
  end

  describe 'active' do
    using RSpec::Parameterized::TableSyntax

    let(:task) { 'gitlab:db:active' }
    let(:self_monitoring) { double('self_monitoring') }

    where(:needs_migration, :self_monitoring_project, :project_count, :exit_status, :exit_code) do
      true | nil | nil | 1 | false
      false | :self_monitoring | 1 | 1 | false
      false | nil | 0 | 1 | false
      false | :self_monitoring | 2 | 0 | true
    end

    with_them do
      it 'exits 0 or 1 depending on user modifications to the database' do
        allow_any_instance_of(ActiveRecord::MigrationContext).to receive(:needs_migration?).and_return(needs_migration)
        allow_any_instance_of(ApplicationSetting).to receive(:self_monitoring_project).and_return(self_monitoring_project)
        allow(Project).to receive(:count).and_return(project_count)

        expect { run_rake_task(task) }.to raise_error do |error|
          expect(error).to be_a(SystemExit)
          expect(error.status).to eq(exit_status)
          expect(error.success?).to be(exit_code)
        end
      end
    end
  end

  describe '#migrate_with_instrumentation' do
    describe '#up' do
      subject { run_rake_task('gitlab:db:migration_testing:up') }

      it 'delegates to the migration runner' do
        expect(::Gitlab::Database::Migrations::Runner).to receive_message_chain(:up, :run)

        subject
      end
    end

    describe '#down' do
      subject { run_rake_task('gitlab:db:migration_testing:down') }

      it 'delegates to the migration runner' do
        expect(::Gitlab::Database::Migrations::Runner).to receive_message_chain(:down, :run)

        subject
      end
    end
  end

  describe '#execute_batched_migrations' do
    subject { run_rake_task('gitlab:db:execute_batched_migrations') }

    let(:migrations) { create_list(:batched_background_migration, 2) }
    let(:runner) { instance_double('Gitlab::Database::BackgroundMigration::BatchedMigrationRunner') }

    before do
      allow(Gitlab::Database::BackgroundMigration::BatchedMigration).to receive_message_chain(:active, :queue_order).and_return(migrations)
      allow(Gitlab::Database::BackgroundMigration::BatchedMigrationRunner).to receive(:new).and_return(runner)
    end

    it 'executes all migrations' do
      migrations.each do |migration|
        expect(runner).to receive(:run_entire_migration).with(migration)
      end

      subject
    end
  end

  context 'with multiple databases', :reestablished_active_record_base do
    before do
      skip_if_multiple_databases_not_setup
    end

    describe 'db:structure:dump against a single database' do
      it 'invokes gitlab:db:clean_structure_sql' do
        expect(Rake::Task['gitlab:db:clean_structure_sql']).to receive(:invoke).twice.and_return(true)

        expect { run_rake_task('db:structure:dump:main') }.not_to raise_error
      end
    end

    describe 'db:schema:dump against a single database' do
      it 'invokes gitlab:db:clean_structure_sql' do
        expect(Rake::Task['gitlab:db:clean_structure_sql']).to receive(:invoke).once.and_return(true)

        expect { run_rake_task('db:schema:dump:main') }.not_to raise_error
      end
    end

    describe 'db:migrate against a single database' do
      it 'invokes gitlab:db:create_dynamic_partitions for the same database' do
        expect(Rake::Task['gitlab:db:create_dynamic_partitions:main']).to receive(:invoke).once.and_return(true)

        expect { run_rake_task('db:migrate:main') }.not_to raise_error
      end
    end

    describe 'db:migrate:geo' do
      before do
        skip_unless_geo_configured
      end

      it 'does not invoke gitlab:db:create_dynamic_partitions' do
        expect(Rake::Task['gitlab:db:create_dynamic_partitions']).not_to receive(:invoke)

        expect { run_rake_task('db:migrate:geo') }.not_to raise_error
      end
    end
  end

  describe 'gitlab:db:reset_as_non_superuser' do
    let(:connection_pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool ) }
    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
    let(:configurations) { double(ActiveRecord::DatabaseConfigurations) }
    let(:configuration) { instance_double(ActiveRecord::DatabaseConfigurations::HashConfig) }
    let(:config_hash) { { username: 'foo' } }

    it 'migrate as nonsuperuser check with default username' do
      allow(Rake::Task['db:drop']).to receive(:invoke)
      allow(Rake::Task['db:create']).to receive(:invoke)
      allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
      allow(configurations).to receive(:configs_for).and_return([configuration])
      allow(configuration).to receive(:configuration_hash).and_return(config_hash)
      allow(ActiveRecord::Base).to receive(:establish_connection).and_return(connection_pool)

      expect(config_hash).to receive(:merge).with({ username: 'gitlab' })
      expect(Gitlab::Database).to receive(:check_for_non_superuser)
      expect(Rake::Task['db:migrate']).to receive(:invoke)

      run_rake_task('gitlab:db:reset_as_non_superuser')
    end

    it 'migrate as nonsuperuser check with specified username' do
      allow(Rake::Task['db:drop']).to receive(:invoke)
      allow(Rake::Task['db:create']).to receive(:invoke)
      allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
      allow(configurations).to receive(:configs_for).and_return([configuration])
      allow(configuration).to receive(:configuration_hash).and_return(config_hash)
      allow(ActiveRecord::Base).to receive(:establish_connection).and_return(connection_pool)

      expect(config_hash).to receive(:merge).with({ username: 'foo' })
      expect(Gitlab::Database).to receive(:check_for_non_superuser)
      expect(Rake::Task['db:migrate']).to receive(:invoke)

      run_rake_task('gitlab:db:reset_as_non_superuser', '[foo]')
    end
  end

  def run_rake_task(task_name, arguments = '')
    Rake::Task[task_name].reenable
    Rake.application.invoke_task("#{task_name}#{arguments}")
  end

  def expect_multiple_executions_of_task(test_task_name, task_to_invoke, count: 2)
    Rake::Task.define_task(test_task_name => :environment) do
      count.times do
        yield

        Rake::Task[task_to_invoke].invoke
      end
    end

    run_rake_task(test_task_name)
  end

  def skip_unless_geo_configured
    skip 'Skipping because the geo database is not configured' unless geo_configured?
  end

  def geo_configured?
    !!ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: 'geo')
  end
end
