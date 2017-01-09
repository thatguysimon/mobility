module Mobility
  module Backend
    module Sequel
      autoload :Columns,      'mobility/backend/sequel/columns'
      autoload :Dirty,        'mobility/backend/sequel/dirty'
      autoload :Serialized,   'mobility/backend/sequel/serialized'
      autoload :Table,        'mobility/backend/sequel/table'
      autoload :QueryMethods, 'mobility/backend/sequel/query_methods'
    end
  end
end
