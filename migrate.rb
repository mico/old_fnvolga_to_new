# - скопировать картинки с сайта в каталог фн-волги,

require 'mysql2'
require 'byebug'
require 'CSV'

@authors_mapping = CSV.read('mapping/authors.csv').to_h
@category_mapping = CSV.read('mapping/category.csv').to_h
@subcategory_mapping = CSV.read('mapping/subcategory.csv').to_h
@issue_mapping = {}

@images_path = '/Users/mico/Downloads/public_html'

article_migrate = {
  'Title': 'title',
  'SubTitle': 'subtitle',
  'Description': 'introtext',
  'Text': 'fulltext',
  'FROM_UNIXTIME(Date)': %w[published created modified],
  'Author': 'author_id',
  'Picture': 'logo',
  'PicTitle': 'logo_caption',
  'Category': 'article_rubric_id',
  'Subcategory': 'article_rubric_id',
  'Issue': 'newspaper_issue_id'
}

@author_migrate = {
  'FirstName': 'name',
  'SecondName': 'name2',
  'JobTitle': 'occupation',
  'Text': 'description',
  'Photo': 'b_image'
}

@category_migrate = {
  'Title': 'title'
}

@issue_migrate = {
  'YearNum': 'number',
  'TotalNum': 'number',
  'FROM_UNIXTIME(Date)': 'published',
  'Image': 'logo'
}

@client_from = Mysql2::Client.new(host: '127.0.0.1', username: 'root',
                                 database: 'old_fnvolga')
@client_to = Mysql2::Client.new(host: '127.0.0.1', username: 'root',
                               database: 'fn_volga')
@dont_escape = [Time, Fixnum]
# set names 'utf8';
@client_to.query("SET NAMES 'UTF8'")
@client_from.query("SET NAMES 'UTF8'")

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

def migrate_author(id)
  return @authors_mapping[id.to_s].to_i if @authors_mapping.key?(id.to_s)
  res = @client_from.query('SELECT %s FROM Authors WHERE id = %d' %
                           [@author_migrate.keys.join(','), id])
  return unless res.any?
  row = res.first
  res = @client_to.query("SELECT id FROM fs_author WHERE name = '%s' AND name2 = '%s'" %
                          [row['FirstName'], row['SecondName']])

  return res.first['id'] if res.any?
  values = {}
  @author_migrate.map do |k, v|
    values[v] = row[k.to_s]
  end
  q = "INSERT INTO fs_author (`%s`) VALUES ('%s')" %
      [@author_migrate.values.join('`, `'), values.values.join("', '")]
  puts q
  @client_to.query(q)
  @authors_mapping[id.to_s] = @client_to.last_id
end

def migrate_rubric(id, subcategory_id)
  # use subcategory if available
  return @subcategory_mapping[subcategory_id.to_s].to_i if @subcategory_mapping.key?(subcategory_id.to_s)
  return @category_mapping[id.to_s].to_i if @category_mapping.key?(id.to_s)
  if subcategory_id.empty?
    res = @client_from.query('SELECT %s FROM Category WHERE id = %d' %
                             [@category_migrate.keys.join(','), id])
  else
    res = @client_from.query('SELECT %s FROM Subcategory WHERE id = %d' %
                             [@category_migrate.keys.join(','), subcategory_id])
  end
  return unless res.any?
  values = {}
  values['state'] = 1
  @category_migrate.map do |k, v|
    values[v] = res.first[k.to_s]
  end

  q = "INSERT INTO fs_newspaper_article_rubric (`%s`) VALUES ('%s')" %
      [(@category_migrate.values.uniq + ['state']).join('`, `'), values.values.join("', '")]
  puts q
  @client_to.query(q)
  # save created category
  @category_mapping[id] = @client_to.last_id
end

def migration(mapping, migrate_map, table, table_to, id, add_state = false)
  return mapping[id] if mapping.key?(id)
  res = @client_from.query(
    format('SELECT %<keys>s FROM `%<table>s` WHERE id = %<id>d',
           keys: migrate_map.keys.join(','),
           table: table,
           id: id)
  )
  return unless res.any?

  values = migrate_map.map { |k, v| [v.to_sym, res.first[k.to_s]] }.to_h
  values['state'] = 1 if add_state
  values.merge!(yield(res)) if block_given?

  q = format("INSERT INTO %<table_to>s (`%<keys>s`) VALUES ('%<values>s')",
             table_to: table_to,
             keys: values.keys.join('`, `'),
             values: values.values.join("', '"))
  puts q
  @client_to.query(q)
  @client_to.last_id
end

def migrate_issue(id)
  last_id = migration(@issue_mapping, @issue_migrate,
                      'Issues', 'fs_newspaper_issue', id, true) do |res|
    { 'number': "#{res.first['YearNum']} (#{res.first['TotalNum']})" }
  end
  @issue_mapping[id] = last_id
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

@client_from.query('SELECT %s FROM Articles' %
                  article_migrate.keys.join(',')).each do |row|
  values = make_migration(article_migrate, row)
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
