class Migration < GenericMigration
  def initialize(entity, config, entity_id = nil)
    @entity = entity
    @entity_id = entity_id
    @config = config
  end

  def relations_with_ids
    get_data(make_query).map do |data|
      break if relations.empty?

      yield(relations.map { |relation, _| [relation.downcase, data[relation]] })
    end
  end

  def fields
    # add many to many relation to fields
    @config[@entity][:fields].keys + relations.select { |_, relation_config| relation_config[:type] == 'manytomany' }
                                              .map(&:first)
  end

  def client_from
    client = Mysql2::Client.new($settings[$settings['environment']]['from'])
    client
  end

  def client_to
    client = Mysql2::Client.new($settings[$settings['environment']]['to'])
    client.query("SET NAMES 'UTF8'")
    client
  end

  def get_data(query)
    @get_data ||= $client_from.query(query)
  end

  def get_data_from_destination(query)
    $client_to.query(query)
  end

  def update_data(query)
    $client_to.query(query)
    $client_to.last_id
  end

  def migrate_entity(relation, id)
    update_data(Migration.new(relation.downcase, @config, id).queries.first)
  end

  def migrate_data(data)
    updated_entities_ids = {}
    data.each do |row|
      migration_row = MigrationRow.new(@config[@entity], mappings, row)
      migration_row.make_relation_queries do |relation, id|
        updated_entities_ids[relation.downcase] = migrate_entity(relation, id)
      end
      updated_entities_ids[@entity] = update_data(migration_row.get_query)
      update_data(migration_row.manytomany_query(updated_entities_ids))
    end
  end


  def real_migrate(data)
    migrate_data(data) do |query|
      id = update_data(query)
    end
  end

  def make_query
    query = format(('SELECT %<fields>s FROM %<table>s' +
                   (!@entity_id && test_env? && ' limit 10' || '') +
                   (@entity_id && format(' WHERE id = %<id>s', id: @entity_id) || '')),
                   fields: fields.join(', '),
                   table: @config[@entity][:from])
    query
  end

  def mappings
    @mappings ||= Dir['mapping/*csv'].map do |mapping|
      name = mapping.sub('.csv', '').sub('mapping/', '')
      [name, CSV.read(mapping).to_h]
    end.to_h || { 'issue': {} }
  end

  def queries
    migrate_data(get_data(make_query))
  end

  def run
    data = migrate_data(get_data)
    update_data(data.join(";\n") + ";\n")
  end
end
