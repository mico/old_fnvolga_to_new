class MigrationRow < GenericMigration
  def initialize(config, mappings, row)
    @row = row
    @config = config
    @mappings = mappings
    @needed_relations = {}
    prepare_update_values
    prepare_relation_values
  end

  def set_relation_value(relation, value)
    # skip already found relations (if duplicates in migration description)
    destination_field = @config[:fields][relation]
    # next if values.key?(destination_field)
    @values[destination_field] = value
  end

  def prepare_relation_values
    # one to many relations
    relations.each do |relation, params|
      next unless params[:type] == 'belongs_to'
      next if params.key?(:convert_to) && params[:convert_to] == 'manytomany'

      relation_id = @row[relation]
      next unless relation_id

      entity = relation.downcase
      # XXX: only one place @mappings is using
      if @mappings[entity] && @mappings[entity][relation_id]
        set_relation_value(relation, @mappings[entity][relation_id])
      else
        @needed_relations[relation] = relation_id
      end
    end
  end

  def prepare_update_values
    @values = @config[:fields].map { |key, value| [value, @row[key]] }.to_h
    # eval custom fields
    if @config.key?(:custom_fields)
      @config[:custom_fields].each do |field, code|
        @values[field.to_sym] = code.is_a?(String) && code.gsub(/\#\{(.*?)\}/) { eval($1) } || code
      end
    end
  end

  def make_relation_queries
    @needed_relations.each do |relation, id|
      set_relation_value(relation, yield(relation, id))
    end
  end

  def make_update_query
    query = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
    table_to: @config[:to],
    keys: @values.keys.join('`, `'),
    values: @values.values.join("', '"))
  end

  def get_query
    search_mapping = @config[:search_mapping]

    # TODO: update later
    if search_mapping # XXX: not working in tests now
      query = format('SELECT id FROM %<table_to>s WHERE %<condition>s',
                      table_to: migrate_to,
                      condition: search_mapping.to_a.map{|k, v| "#{v} = '#{row_from[k.to_s]}'"}.join(' AND '))
      result = get_data_from_destination(query)
      return result.first['id'] if result.any?
    end

    return make_update_query
    @client_to.query(make_update_query)
    last_id = @client_to.last_id

    # update after insert
    update_after_insert = @config['update_after_insert']
    if update_after_insert
      updates = update_after_insert.map do |field, code|
        "`#{field}` = '#{escape(code.gsub(/\#\{(.*?)\}/) { eval($1) })}'"
      end.join(', ')
      query = format("UPDATE %<table_to>s SET %<updates>s WHERE id = %<id>d",
        table_to: migrate_to,
        updates: updates,
        id: last_id)
      @client_to.query(query)
    end

    # many to many relations migrate
    manytomany_relations.each do |relation, params|
      # manytomany
      entity_id = migrate_entity(relation.downcase, row[relation])
      next unless entity_id
      @client_to.query(
        format('INSERT INTO %<table>s (%<foreign_id_name>s, %<primary_id_name>s) VALUES (%<foreign_id>d, %<primary_id>d)',
                table: params['table'],
                foreign_id_name: params['foreign_id'],
                primary_id_name: params['primary_id'],
                foreign_id: last_id,
                primary_id: entity_id)
      )
    end

    last_id
  end
end
