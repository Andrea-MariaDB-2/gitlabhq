# frozen_string_literal: true

module Gitlab
  module Database
    module QueryAnalyzers
      class RestrictAllowedSchemas < Base
        UnsupportedSchemaError = Class.new(QueryAnalyzerError)
        DDLNotAllowedError = Class.new(UnsupportedSchemaError)
        DMLNotAllowedError = Class.new(UnsupportedSchemaError)
        DMLAccessDeniedError = Class.new(UnsupportedSchemaError)

        IGNORED_SCHEMAS = %i[gitlab_shared].freeze

        class << self
          def enabled?
            true
          end

          def allowed_gitlab_schemas
            self.context[:allowed_gitlab_schemas]
          end

          def allowed_gitlab_schemas=(value)
            self.context[:allowed_gitlab_schemas] = value
          end

          def analyze(parsed)
            # If list of schemas is empty, we allow only DDL changes
            if self.dml_mode?
              self.restrict_to_dml_only(parsed)
            else
              self.restrict_to_ddl_only(parsed)
            end
          end

          def require_ddl_mode!(message = "")
            return unless self.context

            self.raise_dml_not_allowed_error(message) if self.dml_mode?
          end

          def require_dml_mode!(message = "")
            return unless self.context

            self.raise_ddl_not_allowed_error(message) if self.ddl_mode?
          end

          private

          def restrict_to_ddl_only(parsed)
            tables = self.dml_tables(parsed)
            schemas = self.dml_schemas(tables)

            if schemas.any?
              self.raise_dml_not_allowed_error("Modifying of '#{tables}' (#{schemas.to_a}) with '#{parsed.sql}'")
            end
          end

          def restrict_to_dml_only(parsed)
            if parsed.pg.ddl_tables.any?
              self.raise_ddl_not_allowed_error("Modifying of '#{parsed.pg.ddl_tables}' with '#{parsed.sql}'")
            end

            if parsed.pg.ddl_functions.any?
              self.raise_ddl_not_allowed_error("Modifying of '#{parsed.pg.ddl_functions}' with '#{parsed.sql}'")
            end

            tables = self.dml_tables(parsed)
            schemas = self.dml_schemas(tables)

            if (schemas - self.allowed_gitlab_schemas).any?
              raise DMLAccessDeniedError, "Select/DML queries (SELECT/UPDATE/DELETE) do access '#{tables}' (#{schemas.to_a}) " \
                "which is outside of list of allowed schemas: '#{self.allowed_gitlab_schemas}'."
            end
          end

          def dml_mode?
            self.allowed_gitlab_schemas&.any?
          end

          def ddl_mode?
            !self.dml_mode?
          end

          def dml_tables(parsed)
            parsed.pg.select_tables + parsed.pg.dml_tables
          end

          def dml_schemas(tables)
            extra_schemas = ::Gitlab::Database::GitlabSchema.table_schemas(tables)
            extra_schemas.subtract(IGNORED_SCHEMAS)
            extra_schemas
          end

          def raise_dml_not_allowed_error(message)
            raise DMLNotAllowedError, "Select/DML queries (SELECT/UPDATE/DELETE) are disallowed in the DDL (structure) mode. #{message}"
          end

          def raise_ddl_not_allowed_error(message)
            raise DDLNotAllowedError, "DDL queries (structure) are disallowed in the Select/DML (SELECT/UPDATE/DELETE) mode. #{message}"
          end
        end
      end
    end
  end
end
