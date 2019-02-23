require_relative '../lib/migrate'

RSpec.describe 'migration' do
  it 'should migrate data based on config' do
    config = { fields: { Title: 'title' }, from: 'Articles' }
    migration = Migration.new('article', config)
    expect(migration.make_query).to eq('SELECT Title FROM Articles limit 10')
    row = { 'Title': 'just a title' }
    expect(migration.migration_row_query({}, config, row))
      .to eq("INSERT INTO  (`title`) VALUES ('just a title')")
  end
end
