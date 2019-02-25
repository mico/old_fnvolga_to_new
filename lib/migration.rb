class Migration < GenericMigration
  def initialize(entity, config, entity_id = nil)
    @entity = entity
    @entity_id = entity_id
    @config = config
  end

  def manytomany_relations
    relations.select do |_, params|
      params[:type] == 'manytomany'
    end
  end

  def relations_with_ids
    get_data.map do |data|
      break if relations.empty?

      yield(relations.map { |relation, _| [relation.downcase, data[relation]] })
    end
  end

  def fields
    # add many to many relation to fields
    @config[:fields].keys + relations.select { |_, relation_config| relation_config[:type] == 'manytomany' }
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

  def get_data
    @get_data ||= $client_from.query(make_query)
  end

  def get_data_from_destination(query)
    $client_to.query(query)
  end

  def update_data(query)
    $client_to.query(query)
  end

  def migrate_data(data)
    data.map do |row|
      migration_row = MigrationRow.new(@config, mappings, row)
      migration_row.get_query
    end
  end

  def make_query
    query = format(('SELECT %<fields>s FROM %<table>s' +
                   (!@entity_id && test_env? && ' limit 10' || '') +
                   (@entity_id && format(' WHERE id = %<id>s', id: @entity_id) || '')),
                   fields: fields.join(', '),
                   table: @config[:from])
    query
  end

  def mappings
    @mappings ||= Dir['mapping/*csv'].map do |mapping|
      name = mapping.sub('.csv', '').sub('mapping/', '')
      [name, CSV.read(mapping).to_h]
    end.to_h || { 'issue': {} }
  end

  def run
    data = migrate_data(get_data)
    update_data(data.join(";\n") + ";\n")
  end
end
