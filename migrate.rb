require 'mysql2'

client_from = Mysql2::Client.new(host: '127.0.0.1', username: 'root',
                                 database: 'old_fnvolga')
client_to = Mysql2::Client.new(host: '127.0.0.1', username: 'root',
                               database: 'fn_volga')
client_from.query('SELECT * FROM Articles limit 1').each do |row|
  puts row['Title']
  puts row['Subtitle']
  puts row['Text']
end
