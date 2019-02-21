require 'mysql2'
require 'byebug'
require 'CSV'
require 'yaml'

@mappings = {'issue': {}}
Dir['mapping/*csv'].each do |mapping|
  name = migration.sub('.csv', '').sub('mapping/', '')
  @mappings[name] = CSV.read(mapping).to_h
end

@migrations = {}

# Issues
# Я обложки сделал для выпусков, могу их загрузить в стандартный каталог для обложек к выпускам -  /htdocs/f/i/newspaper_issue/logo
# Имя файла, как я тебе говорил, сделаю по маске [TotalNum]_[YearNum].jpg
# то что, есть в Image - удали

# Articles
# Там в поле Picture прописан адрес картинки. Тебе из него надо удалить images/
# Оставить только имя файла

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

def make_migration(mapping, row)
  values = {}
  mapping.map do |k, v|
    if v.is_a?(Array)
      v.each do |r|
        values[r] = escape(row[k.to_s])
      end
    else
      values[v] = escape(row[k.to_s])
    end
  end
  values
end

def migration(mapping, migrate_map, id)
  return mapping[id] if mapping.key?(id)
  fields = migrate_map['fields']
  res = @client_from.query(
    format('SELECT %<keys>s FROM `%<table>s` WHERE id = %<id>d',
           keys: fields.keys.join(','),
           table: migrate_map['from'],
           id: id)
  )
  return unless res.any?

  row_from = res.first
  search_mapping = migrate_map['search_mapping']
  migrate_to = migrate_map['to']

  if search_mapping
    query = format('SELECT id FROM %<table_to>s WHERE %<condition>s',
                   table_to: migrate_to,
                   condition: search_mapping.to_a.map{|k, v| "#{v} = '#{row_from[k.to_s]}'"}.join(' AND '))
    result = @client_to.query(query)
    return result.first['id'] if result.any?
  end

  values = fields.map { |key, value| [value.to_sym, row_from[key.to_s]] }.to_h
  migrate_map['custom_fields'].each do |field, code|
    values[field.to_sym] = code.is_a?(String) && code.gsub(/\#\{(.*?)\}/) { eval($1) } || code
  end

  query = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
                 table_to: migrate_to,
                 keys: values.keys.join('`, `'),
                 values: values.values.join("', '"))
  puts query
  @client_to.query(query)
  last_id = @client_to.last_id
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
  last_id
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

def create_insert(keys, values)
  format("INSERT INTO fs_newspaper_article (`%<keys>s`) VALUES ('%<values>s')",
         keys: keys.join('`, `'),
         values: values.join("', '"))
end

def manytomany_relations
  relations.select do |_, params|
    params['type'] == 'manytomany'
  end
end

def run
  fields = @migrations['article']['fields']
  # TODO: add manytomany relations to fields
  # if relations.has_manytomany?
  #   fields << relations.manytomany.fields
  fields += manytomany_relations.map { |relation, _| relation }
  query = ('SELECT %s FROM Articles' + (test_env? && ' limit 10' || '')) %
           fields.keys.join(', ')
  puts query
  @client_from.query(query).each do |row|
    values = make_migration(fields, row)
    values['state'] = 1

    # rubric
    if row['Subcategory']
      article_rubric_id = migrate_entity('subcategory', row['Subcategory'])
    else
      article_rubric_id = migrate_entity('category', row['Category'])
    end
    values['article_rubric_id'] = article_rubric_id if article_rubric_id

    relations = @migrations['article']['relations']
    if relations
      relations.each do |relation, params|
        next unless params['type'] == 'onetomany'
        values[fields[relation]] = migrate_entity(relation.downcase, row[relation])
      end
    end

    puts create_insert(values.keys, values.values.map { |v| v.is_a?(String) && v.truncate || v })
    @client_to.query(create_insert(values.keys, values.values))

    last_id = @client_to.last_id

    if relations
      relations.each do |relation, params|
        next unless params['type'] == 'manytomany'
        # manytomany
        entity_id = migrate_entity(relation.downcase, row[relation])
        if entity_id
          @client_to.query(
            format('INSERT INTO %<table>s (%<foreign_id_name>s, %<primary_id_name>s) VALUES (%<foreign_id>d, %<primary_id>d)',
                  table: params['table'],
                  foreign_id_name: params['foreign_id'],
                  primary_id_name: params['primary_id'],
                  foreign_id: last_id,
                  primary_id: entity_id)
          )
        end
      end
    end
  end
end
