# frozen-string-literal: true
module Mobility
  module Arel
    class Visitor < ::Arel::Visitors::Visitor
      INNER_JOIN = ::Arel::Nodes::InnerJoin
      OUTER_JOIN = ::Arel::Nodes::OuterJoin

      attr_reader :backend_class

      def initialize(backend_class = nil)
        super()
        @backend_class = backend_class
      end

      private

      def visit(object)
        super
      rescue TypeError
      end

      def visit_collection(objects)
        objects.find(&method(:visit))
      end
      alias :visit_Array :visit_collection

      def visit_Arel_Nodes_Unary(object)
        visit(object.expr)
      end

      def visit_Arel_Nodes_Binary(object)
        visit_collection([object.left, object.right])
      end

      def visit_Arel_Nodes_Function(object)
        visit_collection(object.expressions)
      end

      def visit_Arel_Nodes_Case(object)
        visit_collection([object.case, object.conditions, object.default])
      end

      def visit_Arel_Nodes_And(object)
        visit_Array(object.children)
      end

      def visit_Arel_Nodes_Node(_)
      end

      def visit_Arel_Attributes_Attribute(_)
      end
    end
  end
end
