require 'active_record'

module ChronoModel
  module Patches

    # Patches ActiveRecord::Associations::Association to add support for
    # temporal associations.
    #
    # Each record fetched from the +as_of+ scope on the owner class will have
    # an additional "as_of_time" field yielding the UTC time of the request,
    # then the as_of scope is called on this association's class.
    #
    # This behaviour is enabled iff both the owner and the target are temporal
    # aware models, and this is an association called on a temporal scope.
    #
    class Association < ActiveRecord::Associations::Association
      def scoped
        return super unless chrono?
        super.as_of(owner.as_of_time)
      end

      private
        def chrono?
          owner.class.chrono? && reflection.klass.chrono? && owner.as_of_time.present?
        end
    end

    # Adds the WITH queries (Common Table Expressions) support to
    # ActiveRecord::Relation.
    #
    # \name  is the CTE you want
    # \value can be a plain SQL query or another AR::Relation
    #
    # Example:
    #
    #   Post.with('posts',
    #     Post.from('history.posts').
    #       where('? BETWEEN valid_from AND valid_to', 1.month.ago)
    #   ).where(:author_id => 1)
    #
    # yields:
    #
    #   WITH posts AS (
    #     SELECT * FROM history.posts WHERE ... BETWEEN valid_from AND valid_to
    #   ) SELECT * FROM posts
    #
    # PG Documentation:
    # http://www.postgresql.org/docs/9.0/static/queries-with.html
    #
    module QueryMethods
      attr_accessor :with_values

      def with(name, value)
        clone.tap do |relation|
          relation.with_values ||= {}
          value = value.to_sql if value.respond_to? :to_sql
          relation.with_values[name] = value
        end
      end

      # FIXME this parameter passing is ugly - refactor it.
      def temporal(time, table, history)
        @temporal ||= time

        readonly.with(
          table, unscoped.
            select("#{history}.*, '#@temporal' AS as_of_time").
            from(history).
            where("'#@temporal' BETWEEN valid_from AND valid_to")
        )
      end

      def build_arel
        super.tap do |arel|
          arel.with with_values if with_values.present?

          if @temporal
            arel.join_sources.each do |join|
              if connection.is_chrono? join.left.name
                temporal(nil, join.left.name, "#{Adapter::HISTORY_SCHEMA}.#{join.left.name}")
              end
            end
          end

        end
      end
    end

    module Querying
      delegate :with, :to => :scoped
    end

    # Fixes ARel's WITH visitor method with the correct SQL syntax
    #
    # FIXME: the .children.first is messy. This should be properly
    # fixed in ARel.
    #
    class Visitor < Arel::Visitors::PostgreSQL
      def visit_Arel_Nodes_With o
        values = o.children.first.map do |name, value|
          [name, ' AS (', value.is_a?(String) ? value : visit(value), ')'].join
        end
        "WITH #{values.join ', '}"
      end
    end

  end
end
