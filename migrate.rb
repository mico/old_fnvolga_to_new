# В общем, статьи и выпуски газет с него надо присоединить к фн-волге и переформатировать:
# - скопировать картинки с сайта в каталог фн-волги,
# - поменять в таблицах ссылки на них
# Выпуски - 208 штук
# И еще сравнивать порядка 50 рубрик, и авторов десятка два. Но это я вручную могу сделать и создать недостающих

require 'mysql2'
require 'byebug'
require 'CSV'

@authors_mapping = CSV.read('mapping/authors.csv').to_h
@category_mapping = CSV.read('mapping/category.csv').to_h
@subcategory_mapping = CSV.read('mapping/subcategory.csv').to_h

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
  'Subcategory': 'article_rubric_id' }

@author_migrate = {
  'FirstName': 'name',
  'SecondName': 'name2',
  'JobTitle': 'occupation',
  'Text': 'description',
  'Photo': 'b_image',
}

@category_migrate = {
  'Title': 'title'
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
  res.first.tap do |row|
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
  return @client_to.last_id
  end
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
    values[v] = row[k.to_s]
  end
  q = "INSERT INTO fs_newspaper_article_rubric (`%s`) VALUES ('%s')" %
      [@category_migrate.values.join('`, `'), values.values.join("', '")]
  @client_to.query(q)
  @client_to.last_id
end

@client_from.query('SELECT %s FROM Articles limit 2' %
                  article_migrate.keys.join(',')).each do |row|
  values = make_migration(article_migrate, row)
  values['state'] = 1
  author_id = migrate_author(row['Author'])
  values.delete('author_id')

  article_rubric_id = migrate_rubric(row['Category'], row['Subcategory'])
  values['article_rubric_id'] = article_rubric_id if article_rubric_id

  @client_to.query("INSERT INTO fs_newspaper_article (`%s`) VALUES ('%s')" %
                  [values.keys.join('`, `'), values.values.join("', '")])
  article_id = @client_to.last_id
  puts "article_id: #{article_id}"
  puts "author_id: #{author_id}"
  puts "rubric_id: #{article_rubric_id}"

  if author_id
    @client_to.query('INSERT INTO fs_newspaper_article_author (newspaper_article_id, author_id) VALUES (%d, %d)' %
                     [article_id, author_id])
  end

end
