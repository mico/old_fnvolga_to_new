require 'mysql2'
require 'byebug'
require 'CSV'
require 'yaml'

@authors_mapping = CSV.read('mapping/authors.csv').to_h
@category_mapping = CSV.read('mapping/category.csv').to_h
@subcategory_mapping = CSV.read('mapping/subcategory.csv').to_h
@issue_mapping = {}

@migrations = {}

# Issues
# Я обложки сделал для выпусков, могу их загрузить в стандартный каталог для обложек к выпускам -  /htdocs/f/i/newspaper_issue/logo
# Имя файла, как я тебе говорил, сделаю по маске [TotalNum]_[YearNum].jpg
# то что, есть в Image - удали

# Articles
# Там в поле Picture прописан адрес картинки. Тебе из него надо удалить images/
# Оставить только имя файла

@images_path = '/Users/mico/Downloads/public_html'

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


def migrate_rubric(id, subcategory_id)
  # use subcategory if available
  return @subcategory_mapping[subcategory_id.to_s].to_i if @subcategory_mapping.key?(subcategory_id.to_s)
  return @category_mapping[id.to_s].to_i if @category_mapping.key?(id.to_s)
  if subcategory_id.empty?
    res = @client_from.query('SELECT %s FROM Category WHERE id = %d' %
                             [@migrations['category']['fields'].keys.join(','), id])
  else
    res = @client_from.query('SELECT %s FROM Subcategory WHERE id = %d' %
                             [@migrations['category']['fields'].keys.join(','), subcategory_id])
  end
  return unless res.any?
  values = {}
  values['state'] = 1
  @migrations['category']['fields'].map do |k, v|
    values[v] = res.first[k.to_s]
  end

  q = "INSERT INTO fs_newspaper_article_rubric (`%s`) VALUES ('%s')" %
      [(@migrations['category']['fields'].values.uniq + ['state']).join('`, `'), values.values.join("', '")]
  puts q
  @client_to.query(q)
  # save created category
  @category_mapping[id] = @client_to.last_id
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
  updates = migrate_map['update_after_insert'].map do |field, code|
    "`#{field}` = '#{escape(code.gsub(/\#\{(.*?)\}/) { eval($1) })}'"
  end.join(', ')
  query = format("UPDATE %<table_to>s SET %<updates>s WHERE id = %<id>d",
    table_to: migrate_to,
    updates: updates,
    id: last_id)
  puts query
  @client_to.query(query)
  last_id
end

def migrate_issue(id)
  last_id = migration(@issue_mapping, @migrations['issue'], id)
  @issue_mapping[id] = last_id
  last_id
end

def migrate_author(id)
  last_id = migration(@authors_mapping, @migrations['author'], id)
  @authors_mapping[id.to_s] = last_id
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

def run
  query = ('SELECT %s FROM Articles' + (test_env? && ' limit 10' || '')) %
           @migrations['article']['fields'].keys.join(', ')
  puts query
  @client_from.query(query).each do |row|
    values = make_migration(@migrations['article']['fields'], row)
    values['state'] = 1
    author_id = migrate_author(row['Author'])
    values.delete('author_id')

    article_rubric_id = migrate_rubric(row['Category'], row['Subcategory'])
    values['article_rubric_id'] = article_rubric_id if article_rubric_id

    values['newspaper_issue_id'] = migrate_issue(row['Issue']) || nil

    puts create_insert(values.keys, values.values.map { |v| v.is_a?(String) && v.truncate || v })
    @client_to.query(create_insert(values.keys, values.values))
    article_id = @client_to.last_id

    if author_id
      @client_to.query('INSERT INTO fs_newspaper_article_author (newspaper_article_id, author_id) VALUES (%d, %d)' %
                      [article_id, author_id])
    end
  end
end