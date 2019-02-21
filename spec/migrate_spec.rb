require_relative '../lib/migrate'

not_exist_author_id = 1
exist_author_ids = [2, 3]

RSpec.describe 'migration' do
  # shoud convert data like
  # Article
  # id 10, title 'my title', subtitle 'my subtitle'
  # to fs_articles
  # new id, another_title, another_subtitle
  # create new relations if entity has it
  it 'should create author if not exist' do
    expect(migrate_author(not_exist_author_id)).to eq(new_id)
  end
  it 'should use stored author id instead of looking again'
  it 'should create rubric if not exist'
  it 'should create rubric id instead of creating again'
  it 'should create issue...'
  it 'should not have any duplicates' do
    # check issue by YearNum and TotalNum
    # check article by 'Title', 'subtitle', '
  end
end
