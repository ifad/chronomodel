require 'active_record'

module ChronoModel
  module Patches

    # Patches ActiveRecord::Associations::Association to add support for
    # temporal associations.
    #
    # Each record fetched from the +as_of+ scope on the owner class will have
    # an additional "as_of_time" field yielding the UTC time of the request,
    # then the as_of scope is called on either this association's class or
    # on the join model's (:through association) one.
    #
    class Association < ActiveRecord::Associations::Association

      # Add temporal Common Table Expressions (WITH queries) to the resulting
      # scope, checking whether either the association class or the through
      # association one are ChronoModels.
      def scoped
        return super unless _chrono_record?

        ctes = {}

        if reflection.klass.chrono?
          ctes.update _chrono_ctes_for(reflection.klass)
        end

        if respond_to?(:through_reflection) && through_reflection.klass.chrono?
          ctes.update _chrono_ctes_for(through_reflection.klass)
        end

        scoped = super
        ctes.each {|table, cte| scoped = scoped.with(table, cte) }
        return scoped
      end

      private
        def _chrono_ctes_for(klass)
          klass.as_of(owner.as_of_time).with_values
        end

        def _chrono_record?
          owner.respond_to?(:as_of_time) && owner.as_of_time.present?
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

      def build_arel
        super.tap {|arel| arel.with with_values if with_values.present? }
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
