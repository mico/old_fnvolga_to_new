require 'mysql2'
require 'byebug'
require 'CSV'
require 'yaml'

@mappings = { 'issue' => {} }
Dir['mapping/*csv'].each do |mapping|
  name = mapping.sub('.csv', '').sub('mapping/', '')
  @mappings[name] = CSV.read(mapping).to_h
end

@migrations = {}

Dir['migrations/*yml'].each do |migration|
  name = migration.sub('.yml', '').sub('migrations/', '')
  @migrations[name] = YAML.load_file(migration)
end

@settings = YAML.load_file('settings.yml')

@client_from = Mysql2::Client.new(@settings[@settings['environment']]['from'])
@client_to = Mysql2::Client.new(@settings[@settings['environment']]['to'])

@dont_escape = [Time, Fixnum]
# set names 'utf8';
@client_to.query("SET NAMES 'UTF8'")
@client_from.query("SET NAMES 'UTF8'")

def test_env?
  @settings['environment'] == 'test'
end

def escape(string)
  @dont_escape.include?(string.class) && string || @client_from.escape(string)
end

def migration_row(mapping, migrate_map, row_from)
  search_mapping = migrate_map['search_mapping']
  migrate_to = migrate_map['to']

  if search_mapping
    query = format('SELECT id FROM %<table_to>s WHERE %<condition>s',
                   table_to: migrate_to,
                   condition: search_mapping.to_a.map{|k, v| "#{v} = '#{row_from[k.to_s]}'"}.join(' AND '))
    result = @client_to.query(query)
    return result.first['id'] if result.any?
  end

  values = {}
  fields = migrate_map['fields']
  fields.each do |key, value|
    if value.is_a?(Array)
      value.each { |v| values[v.to_sym] = row_from[key.to_s] }
    else
      values[value.to_sym] = row_from[key.to_s]
    end
  end
  migrate_map['custom_fields'].each do |field, code|
    values[field.to_sym] = code.is_a?(String) && code.gsub(/\#\{(.*?)\}/) { eval($1) } || code
  end

  relations = migrate_map['relations']

  # one to many relations
  if relations
    relations.each do |relation, params|
      next unless params['type'] == 'onetomany'
      relation_id = row_from[relation]
      next unless relation_id
      # skip already found relations (if duplicates in migration description)
      next if values.key?(fields[relation])
      values[fields[relation].to_sym] = migrate_entity(relation.downcase, relation_id)
    end
  end

  query = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
                 table_to: migrate_to,
                 keys: values.keys.join('`, `'),
                 values: values.values.map { |v| escape(v) }.join("', '"))
  query_print = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
                 table_to: migrate_to,
                 keys: values.keys.join('`, `'),
                 values: values.values.map{ |v| v.is_a?(String) && v.truncate || v }.join("', '"))

  puts query_print
  @client_to.query(query)
  last_id = @client_to.last_id

  # update after insert
  update_after_insert = migrate_map['update_after_insert']
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

  # many to many relations
  if relations
    manytomany_relations(relations).each do |relation, params|
      # manytomany
      entity_id = migrate_entity(relation.downcase, row_from[relation])
      next unless entity_id
      query = format('INSERT INTO %<table>s (%<foreign_id_name>s, %<primary_id_name>s) VALUES (%<foreign_id>d, %<primary_id>d)',
              table: params['table'],
              foreign_id_name: params['foreign_id'],
              primary_id_name: params['primary_key'],
              foreign_id: last_id,
              primary_id: entity_id)
      puts query
      @client_to.query(query)
    end
  end

  last_id
end

def migration(mapping, migrate_map, id)
  return mapping[id] if mapping.key?(id)
  fields = get_fields(migrate_map)
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

def manytomany_relations(relations)
  relations.select do |_, params|
    params['type'] == 'manytomany'
  end
end

def get_fields(migrations)
  fields = migrations['fields'].dup
  # TODO: add manytomany relations to fields
  # if relations.has_manytomany?
  #   fields << relations.manytomany.fields
  relations = migrations['relations']
  fields.merge!(manytomany_relations(relations).map { |relation, _| [relation, nil] }.to_h) if relations
  fields
end

def run(entity = 'article')
  migrations = @migrations[entity]
  query = format(('SELECT %<fields>s FROM %<table>s' + (test_env? && ' limit 10' || '')),
                 fields: get_fields(migrations).keys.join(', '),
                 table: migrations['from'])
  puts query
  @client_from.query(query).each do |row|
    migration_row(@mappings[entity], migrations, row)
  end
end
