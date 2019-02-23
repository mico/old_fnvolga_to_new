require 'mysql2'
require 'byebug'
require 'CSV'
require 'yaml'

$mappings = {'issue': {}}
Dir['mapping/*csv'].each do |mapping|
  name = mapping.sub('.csv', '').sub('mapping/', '')
  $mappings[name] = CSV.read(mapping).to_h
end

@migrations = {}

Dir['migrations/*yml'].each do |migration|
  name = migration.sub('.yml', '').sub('migrations/', '')
  @migrations[name] = YAML.load_file(migration)
end

$settings = YAML.load_file('settings.yml')

$client_from = Mysql2::Client.new($settings[$settings['environment']]['from'])
$client_to = Mysql2::Client.new($settings[$settings['environment']]['to'])

$dont_escape = [Time, Fixnum]
# set names 'utf8';
$client_to.query("SET NAMES 'UTF8'")
$client_from.query("SET NAMES 'UTF8'")

def test_env?
  $settings['environment'] == 'test'
end

def escape(string)
  $dont_escape.include?(string.class) && string || @client_from.escape(string)
end



def migration(mapping, migrate_map, id)
  return mapping[id] if mapping.key?(id)
  fields = get_fields(@migration[entity])
  res = @client_from.query(
    format('SELECT %<keys>s FROM `%<table>s` WHERE id = %<id>d',
           keys: fields.keys.join(','),
           table: migrate_map['from'],
           id: id)
  )
  return unless res.any?

  migration_row(mapping, migrate_map, res.first)
end

def migrate_entity(entity, id)
  last_id = migration(@mappings[entity], @migrations[entity], id)
  @mappings[entity][id] = last_id
  last_id
end

class String
  def truncate(max = 10)
    length > max ? "#{self[0...max]}..." : self
  end
end

class GenericMigration
  def relations
    @config['relations'] || []
  end
end

class MigrationRow < GenericMigration
  attr_reader :prepare_update_values, :make_update_query

  def initialize(config, mapping, row)
    @row = row
    @config = config
    @mapping = mapping
  end

  def prepare_update_values
    values = @config[:fields].map { |key, value| [value.to_sym, @row[key.to_sym]] }.to_h
    # eval custom fields
    @config[:custom_fields].each do |field, code|
      values[field.to_sym] = code.is_a?(String) && code.gsub(/\#\{(.*?)\}/) { eval($1) } || code
    end if @config[:custom_fields]
    values
  end

  def make_update_query
    query = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
    table_to: @config[:to],
    keys: prepare_update_values.keys.join('`, `'),
    values: prepare_update_values.values.join("', '"))
  end

  def get_query
    search_mapping = @config[:search_mapping]

    # TODO: update later
    if search_mapping
      query = format('SELECT id FROM %<table_to>s WHERE %<condition>s',
                     table_to: migrate_to,
                     condition: search_mapping.to_a.map{|k, v| "#{v} = '#{row_from[k.to_s]}'"}.join(' AND '))
      result = get_data_from_destination(query)
      return result.first['id'] if result.any?
    end

    # one to many relations
    if relations
      relations.each do |relation, params|
        next unless params['type'] == 'onetomany'
        relation_id = row[relation]
        next unless relation_id
        # skip already found relations (if duplicates in migration description)
        next if values.key?(fields[relation])
        values[fields[relation]] = migrate_entity(relation.downcase, relation_id)
      end
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
      puts query
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

class Migration < GenericMigration
  def initialize(entity, config)
    @entity = entity
    @config = config
  end

  def manytomany_relations
    relations.select do |_, params|
      params[:type] == 'manytomany'
    end
  end

  def fields
    # add many to many relation to fields
    @config[:fields].keys + relations.select { |_, relation_config| relation_config[:type] == 'manytomany' }
                                     .map(&:first)
  end

  def get_data(query)
    $client_from.query(query)
  end

  def get_data_from_destination(query)
    $client_to.query(query)
  end

  def update_data(query)
  end

  def migration_row_query(mapping, config, row)
    migration_row = MigrationRow.new(config, mapping, row)
    migration_row.get_query
  end

  def make_query
    query = format(('SELECT %<fields>s FROM %<table>s' + (test_env? && ' limit 10' || '')),
                   fields: fields.join(', '),
                   table: @config[:from])
    puts query
    query
  end

  def run
    get_data(make_query).each do |row|
      migration_row_query(@mapping[@entity], @config, row)
    end
  end
end

def run(entity = 'article')
  migration = Migration.new(entity, @migrations[entity])
  migration.run
end
