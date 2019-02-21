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

def make_migration(mapping, row)
  values = {}
  mapping.map do |k, v|
    if v.is_a?(Array)
      v.each do |r|
        values[r] = @dont_escape.include?(row[k.to_s].class) && row[k.to_s] ||
                    @client_from.escape(row[k.to_s])
      end
    else
      values[v] = @dont_escape.include?(row[k.to_s].class) && row[k.to_s] ||
                  @client_from.escape(row[k.to_s])
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
                             [@migrations['category'].keys.join(','), id])
  else
    res = @client_from.query('SELECT %s FROM Subcategory WHERE id = %d' %
                             [@migrations['category'].keys.join(','), subcategory_id])
  end
  return unless res.any?
  values = {}
  values['state'] = 1
  @migrations['category'].map do |k, v|
    values[v] = res.first[k.to_s]
  end

  q = "INSERT INTO fs_newspaper_article_rubric (`%s`) VALUES ('%s')" %
      [(@migrations['category'].values.uniq + ['state']).join('`, `'), values.values.join("', '")]
  puts q
  @client_to.query(q)
  # save created category
  @category_mapping[id] = @client_to.last_id
end

def migration(mapping, migrate_map, table, table_to, id, search_mapping = nil)
  return mapping[id] if mapping.key?(id)
  res = @client_from.query(
    format('SELECT %<keys>s FROM `%<table>s` WHERE id = %<id>d',
           keys: migrate_map.keys.join(','),
           table: table,
           id: id)
  )
  return unless res.any?

  if search_mapping
    query = format('SELECT id FROM %<table_to>s WHERE %<condition>s',
                   table_to: table_to,
                   condition: search_mapping.to_a.map{|k, v| "#{v} = '#{res.first[k.to_s]}'"}.join(' AND '))
    result = @client_to.query(query)
    return result.first['id'] if result.any?
  end

  values = migrate_map.map { |key, value| [value.to_sym, res.first[key.to_s]] }.to_h
  values.merge!(yield(res)) if block_given?

  query = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
                 table_to: table_to,
                 keys: values.keys.join('`, `'),
                 values: values.values.join("', '"))
  puts query
  @client_to.query(query)
  @client_to.last_id
end

def migrate_issue(id)
  last_id = migration(@issue_mapping, @migrations['issue'],
                      'Issues', 'fs_newspaper_issue', id) do |res|
    row = res.first
    { 'number': "#{row['YearNum']} (#{row['TotalNum']})",
      'state': 1 }
  end
  @issue_mapping[id] = last_id
  last_id
end

def migrate_author(id)
  last_id = migration(@authors_mapping, @migrations['author'],
                      'Authors', 'fs_author', id,
                      FirstName: 'name', SecondName: 'name2')
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
  @client_from.query(('SELECT %s FROM Articles' + (test_env? && ' limit 10' || '')) %
                    @migrations['article'].keys.join(',')).each do |row|
    values = make_migration(@migrations['article'], row)
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