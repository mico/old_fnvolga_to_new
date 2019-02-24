require 'mysql2'
require 'byebug'
require 'csv'
require 'yaml'
require 'generic_migration'
require 'migration_row'
require 'migration'

@migrations = {}

Dir['migrations/*yml'].each do |migration|
  name = migration.sub('.yml', '').sub('migrations/', '')
  @migrations[name] = YAML.load_file(migration)
end

$settings = File.exist?('settings.yml') && YAML.load_file('settings.yml') || { 'environment': 'test' }
$settings.transform_keys!(&:to_sym)

$dont_escape = [Time, Integer]

def test_env?
  $settings[:environment] == 'test'
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

def run(entity = 'article')
  migration = Migration.new(entity, @migrations[entity])
  relations_ids = migration.relations_with_ids.map(&:downcase).map do |relation_entity, entity_id|
    Migration.new(relation_entity, @migrations[relation_entity], entity_id)
  end.map(&:run)
  ids = migration.run(relations_ids)
end
