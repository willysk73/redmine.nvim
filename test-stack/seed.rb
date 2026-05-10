# Seed script run via `rails runner` inside the Redmine container.
# Idempotent: safe to run repeatedly.

# 1. Admin password reset + must_change_passwd cleared.
admin = User.find_by(login: 'admin') or raise 'admin user missing'
admin.password = 'admin123!'
admin.password_confirmation = 'admin123!'
admin.must_change_passwd = false
admin.mail = 'admin@example.com' if admin.mail.blank?
admin.save!(validate: false)
puts "[seed] admin password set"

# 2. Enable REST API.
Setting.rest_api_enabled = '1'
Setting.login_required = '0'
puts "[seed] rest_api_enabled=#{Setting.rest_api_enabled}"

# 3. Make sure admin has an API token.
token = Token.find_or_create_by(user_id: admin.id, action: 'api') do |t|
  t.value = Token.generate_token_value
end
puts "[seed] admin_api_key=#{token.value}"

# 4. Project.
project = Project.find_by(identifier: 'demo') || Project.create!(
  name: 'Demo',
  identifier: 'demo',
  description: 'Demo project for redmine.nvim tests',
  is_public: true,
)
puts "[seed] project_id=#{project.id} identifier=#{project.identifier}"

# Enable issue tracking module if not enabled.
project.enable_module!('issue_tracking') unless project.module_enabled?('issue_tracking')

# Make sure project has at least one tracker.
trackers = Tracker.all.to_a
trackers = [Tracker.create!(name: 'Bug', default_status_id: IssueStatus.first&.id || 1)] if trackers.empty?
project.trackers = trackers
project.save!

# 5. Make admin a member with Manager role on the project.
mgr_role = Role.find_by(name: 'Manager') || Role.first
unless project.members.exists?(user_id: admin.id)
  Member.create!(project: project, user: admin, roles: [mgr_role])
  puts "[seed] admin added as Manager"
end

# 6. Issues.
tracker = trackers.first
status_new = tracker.default_status || IssueStatus.sorted.first
status_in_progress = IssueStatus.find_by(name: 'In Progress') ||
                     IssueStatus.where.not(id: status_new.id).first || status_new
priority_normal = IssuePriority.default || IssuePriority.active.first || IssuePriority.first

seeds = [
  { subject: '이메일 검증 함수 추가', description: "회원가입 폼에 이메일 검증 함수 추가.\n\n- RFC 5322 준수\n- 도메인 MX 체크는 별도 티켓", status: status_in_progress, done_ratio: 60 },
  { subject: '로그인 토큰 만료 처리', description: "JWT 만료 시 401을 잘 던지지 못하고 500을 던지는 버그.", status: status_new, done_ratio: 0 },
  { subject: '사내툴 인스톨러 자동화', description: "신규 입사자 셋업 시간 단축. brew bundle 기반.", status: status_in_progress, done_ratio: 30 },
]

seeds.each do |s|
  issue = Issue.find_by(subject: s[:subject], project_id: project.id)
  if issue
    puts "[seed] issue ##{issue.id} already exists: #{s[:subject]}"
    next
  end
  issue = Issue.new(
    project: project,
    tracker: tracker,
    author: admin,
    assigned_to: admin,
    subject: s[:subject],
    description: s[:description],
    status: s[:status],
    priority: priority_normal,
    done_ratio: s[:done_ratio],
  )
  issue.save!
  puts "[seed] created issue ##{issue.id}: #{s[:subject]}"
end

puts "[seed] done"
