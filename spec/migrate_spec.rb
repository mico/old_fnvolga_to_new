require './migrate'
# rspec??
not_exist_author_id = 1
exist_author = 2

RSpec.describe 'migration' do
  it 'should create author if not exist' do
    id = not_exist_author_id
    expect(migrate_author(id)).to eq(new_id)
  end
  it 'should use stored author id instead of looking again'
  it 'should create rubric if not exist'
  it 'should create rubric id instead of creating again'
  it 'should create issue...'
end
