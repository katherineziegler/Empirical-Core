module Teacher
  extend ActiveSupport::Concern

  include CheckboxCallback


  TRIAL_LIMIT = 250
  TRIAL_START_DATE = Date.parse('1-9-2015') # September 1st 2015

  included do
    has_many :units
    has_one :user_subscription
    has_one :subscription, through: :user_subscription
    has_one :referrer_user
    has_many :referrals_users
    has_one :referrals_user, class_name: 'ReferralsUser', foreign_key: :referred_user_id
  end

  class << self
    delegate :first, :find, :where, :all, :count, to: :scope

    def scope
      User.where(role: 'teacher')
    end
  end

  # Occasionally teachers are populated in the view with
  # a single blank classroom.
  def has_classrooms?
    classrooms_i_teach.any? && !classrooms_i_teach.all?(&:new_record?)
  end

  def classrooms_i_teach
    Classroom.find_by_sql(base_sql_for_teacher_classrooms)
  end

  def classrooms_i_own
    Classroom.find_by_sql("#{base_sql_for_teacher_classrooms} AND ct.role = 'owner'")
  end

  def classrooms_i_coteach
    Classroom.find_by_sql("#{base_sql_for_teacher_classrooms} AND ct.role = 'coteacher'")
  end

  def classroom_ids_i_coteach_or_have_a_pending_invitation_to_coteach
    ids = Set.new
    all_ids = ActiveRecord::Base.connection.execute("SELECT DISTINCT(coteacher_classroom_invitations.classroom_id) AS invitation_id, classrooms_teachers.classroom_id FROM users
      LEFT JOIN invitations ON invitations.invitee_email = users.email AND invitations.archived = false
      LEFT JOIN coteacher_classroom_invitations ON coteacher_classroom_invitations.invitation_id = invitations.id
      LEFT JOIN classrooms_teachers ON classrooms_teachers.user_id = #{self.id} AND classrooms_teachers.role = 'coteacher'
      WHERE users.id = #{self.id}").to_a
      all_ids.each{|row| row.each{|k,v| ids << v}}
      ids
  end

  def ids_of_classroom_teachers_and_coteacher_invitations_that_i_coteach_or_am_the_invitee_of(classrooms_ids_to_check=nil)
    if classrooms_ids_to_check && classrooms_ids_to_check.any?
      # if there are specific ids passed it will only return those that match
      coteacher_classroom_invitation_additional_join = "AND coteacher_classroom_invitations.classroom_id IN (#{classrooms_ids_to_check.map(&:to_i).join(', ')})"
      classrooms_teacher_additional_join = "AND classrooms_teachers.classroom_id IN (#{classrooms_ids_to_check.join(', ')})"
    end
    classrooms_teachers_ids = Set.new
    coteacher_classroom_invitation_ids = Set.new
    all_ids = ActiveRecord::Base.connection.execute("SELECT coteacher_classroom_invitations.id AS coteacher_classroom_invitation_id, classrooms_teachers.id AS classrooms_teachers_id FROM users
      LEFT JOIN invitations ON invitations.invitee_email = users.email AND invitations.archived = false
      LEFT JOIN coteacher_classroom_invitations ON coteacher_classroom_invitations.invitation_id = invitations.id #{coteacher_classroom_invitation_additional_join}
      LEFT JOIN classrooms_teachers ON classrooms_teachers.user_id = #{self.id} AND classrooms_teachers.role = 'coteacher' #{classrooms_teacher_additional_join}
      WHERE users.id = #{self.id}")
      all_ids.each do |row|
        row.each do |k,v|
          if k == 'coteacher_classroom_invitation_id'
            coteacher_classroom_invitation_ids << v.to_i
          elsif k == 'classrooms_teachers_id'
            classrooms_teachers_ids << v.to_i
          end
        end
      end
      {coteacher_classroom_invitations_ids: coteacher_classroom_invitation_ids.to_a, classrooms_teachers_ids: classrooms_teachers_ids.to_a}
  end

  def affiliated_with_unit(unit_id)
    ActiveRecord::Base.connection.execute("SELECT units.id FROM units
      JOIN classroom_activities ON classroom_activities.unit_id = units.id
      JOIN classrooms_teachers ON classroom_activities.classroom_id = classrooms_teachers.classroom_id
      WHERE classrooms_teachers.user_id = #{self.id} AND units.id = #{unit_id.to_i}
      LIMIT(1)").to_a.any?
  end

  def students
    User.find_by_sql(
      "SELECT students.* FROM users AS teacher
      JOIN classrooms_teachers AS ct ON ct.user_id = teacher.id
      JOIN classrooms ON classrooms.id = ct.classroom_id AND classrooms.visible = TRUE
      JOIN students_classrooms AS sc ON sc.classroom_id = ct.classroom_id
      JOIN users AS students ON students.id = sc.student_id
      WHERE teacher.id = #{self.id}"
    )
  end

  def archived_classrooms
    Classroom.find_by_sql("#{base_sql_for_teacher_classrooms(false)} AND ct.role = 'owner' AND classrooms.visible = false")
  end

  def handle_negative_classrooms_from_update_coteachers(classroom_ids=nil)
    if classroom_ids && classroom_ids.any?
      # destroy the extant invitation and teacher relationships
      self.ids_of_classroom_teachers_and_coteacher_invitations_that_i_coteach_or_am_the_invitee_of(classroom_ids).each do |k,v|
        if k == :classrooms_teachers_ids
          ClassroomsTeacher.where(id: v).map(&:destroy)
        elsif k ==  :coteacher_classroom_invitations_ids
          CoteacherClassroomInvitation.where(id: v).map(&:destroy)
        end
      end
    end
  end

  def handle_positive_classrooms_from_update_coteachers(classroom_ids, inviter_id)
    if classroom_ids && classroom_ids.any?
      new_classroom_ids = classroom_ids.map(&:to_i) - self.classroom_ids_i_coteach_or_have_a_pending_invitation_to_coteach.to_a.map(&:to_i)
      if new_classroom_ids.any?
        invitation = Invitation.create(
          invitee_email: self.email,
          inviter_id: inviter_id,
          invitation_type: Invitation::TYPES[:coteacher]
        )
        new_classroom_ids.each do |id|
          CoteacherClassroomInvitation.find_or_create_by(invitation: invitation, classroom_id: id)
        end
      end
    end
  end

  def google_classrooms
    Classroom.find_by_sql("#{base_sql_for_teacher_classrooms} AND ct.role = 'owner' AND classrooms.google_classroom_id IS NOT null")
  end

  def classrooms_i_teach_with_students
    classrooms_i_teach.map{|classroom| classroom.with_students}
  end

  def classrooms_i_teach_with_student_ids
    classrooms_i_teach.map{|classroom| classroom.with_students_ids}
  end

  def classrooms_i_own_with_students
    classrooms_i_own.map{|classroom| classroom.with_students}
  end

  def classrooms_i_am_the_coteacher_for_with_a_specific_teacher_with_students(specified_teacher_id)
    classrooms_i_am_the_coteacher_for_with_a_specific_teacher(specified_teacher_id).map{|classroom| classroom.with_students}
  end

  def classrooms_i_own_that_have_coteachers
    ActiveRecord::Base.connection.execute(
      "SELECT classrooms.name AS name, coteacher.name AS coteacher_name, coteacher.email AS coteacher_email, coteacher.id AS coteacher_id FROM classrooms_teachers AS my_classrooms
      JOIN classrooms_teachers AS coteachers_classrooms ON coteachers_classrooms.classroom_id = my_classrooms.classroom_id
      JOIN classrooms ON coteachers_classrooms.classroom_id = classrooms.id
      JOIN users AS coteacher ON coteachers_classrooms.user_id = coteacher.id
      WHERE my_classrooms.user_id = #{self.id} AND coteachers_classrooms.role = 'coteacher' AND my_classrooms.role = 'owner'").to_a
  end

  def classrooms_i_own_that_have_pending_coteacher_invitations
    ActiveRecord::Base.connection.execute(
      "SELECT DISTINCT classrooms.name AS name, invitations.invitee_email AS coteacher_email FROM classrooms_teachers AS my_classrooms
      JOIN invitations ON invitations.inviter_id = my_classrooms.user_id
      JOIN coteacher_classroom_invitations ON invitations.id = coteacher_classroom_invitations.invitation_id
      JOIN classrooms ON coteacher_classroom_invitations.classroom_id = classrooms.id
      WHERE my_classrooms.user_id = #{self.id} AND invitations.invitation_type = '#{Invitation::TYPES[:coteacher]}' AND invitations.archived = false AND my_classrooms.role = 'owner'").to_a
  end


  def get_classroom_minis_cache
    cache = $redis.get("user_id:#{self.id}_classroom_minis")
    cache ? JSON.parse(cache) : nil
  end

  def set_classroom_minis_cache(info)
    # TODO: move this to background worker
    $redis.set("user_id:#{self.id}_classroom_minis", info.to_json, {ex: 16.hours} )
  end

  def self.clear_classrooms_minis_cache(teacher_id)
    $redis.del("user_id:#{teacher_id}_classroom_minis")
  end

  def get_classroom_minis_info
    cache = get_classroom_minis_cache
    if cache
      return cache
    end
    classrooms = ActiveRecord::Base.connection.execute("SELECT classrooms.name AS name, classrooms.id AS id, classrooms.code AS code, COUNT(DISTINCT sc.id) as student_count  FROM classrooms
			LEFT JOIN students_classrooms AS sc ON sc.classroom_id = classrooms.id
      LEFT JOIN classrooms_teachers ON classrooms_teachers.classroom_id = classrooms.id
			WHERE classrooms.visible = true AND classrooms_teachers.user_id = #{self.id}
			GROUP BY classrooms.name, classrooms.id"
    ).to_a
    counts = ActiveRecord::Base.connection.execute("SELECT classrooms.id AS id, COUNT(DISTINCT acts.id) FROM classrooms
          FULL OUTER JOIN classroom_activities AS class_acts ON class_acts.classroom_id = classrooms.id
          FULL OUTER JOIN activity_sessions AS acts ON acts.classroom_activity_id = class_acts.id
          LEFT JOIN classrooms_teachers ON classrooms_teachers.classroom_id = classrooms.id
          WHERE classrooms_teachers.user_id = #{self.id}
          AND classrooms.visible
          AND class_acts.visible
          AND acts.visible
          AND acts.is_final_score = true
          GROUP BY classrooms.id").to_a
    info = classrooms.map do |classy|
      count = counts.find { |elm| elm['id'] == classy['id'] }
      classy['activity_count'] = count  ? count['count'] : 0
      has_coteacher = ClassroomsTeacher.where(classroom_id: classy['id']).length > 1
      classy['has_coteacher'] = has_coteacher
      classy['teacher_role'] = ClassroomsTeacher.find_by(classroom_id: classy['id'], user_id: self.id).role
      classy
    end
    # TODO: move setter to background worker
    set_classroom_minis_cache(info)
    info
  end

  def google_classrooms
    Classroom.find_by_sql("#{base_sql_for_teacher_classrooms} AND classrooms.google_classroom_id IS NOT NULL")
  end

  def transfer_account
    TransferAccountWorker.perform_async(self.id, new_user.id);
  end

  def classroom_activities(includes_value = nil)
    classroom_ids = classrooms_i_teach.map(&:id)
    if includes_value
      ClassroomActivity.where(classroom_id: classroom_ids).includes(includes_value)
    else
      ClassroomActivity.where(classroom_id: classroom_ids)
    end
  end

  def update_teacher params
    return if !self.teacher?
    params[:role] = 'teacher' if params[:role] != 'student'
    params.permit(:id,
                  :name,
                  :role,
                  :username,
                  :authenticity_token,
                  :email,
                  :time_zone,
                  :password,
                  :school_options_do_not_apply,
                  :school_id,
                  :original_selected_school_id)

    self.validate_username = true

    are_there_school_related_errors = false
    if params[:school_options_do_not_apply] == 'false'
      if params[:school_id].nil? or params[:school_id].length == 0
        are_there_school_related_errors = true
      else
        self.school = School.find(params[:school_id])
        self.updated_school params[:school_id]
        find_or_create_checkbox('Add School', self)
      end
    end
    if !are_there_school_related_errors
      if self.update_attributes(username: params[:username] || self.username,
                                        email: params[:email] || self.email,
                                        name: params[:name] || self.name,
                                        time_zone: params[:time_zone] || self.time_zone,
                                        password: params[:password] || self.password,
                                        role: params[:role] || self.role)
        are_there_non_school_related_errors = false
      else
        are_there_non_school_related_errors = true
      end
    end


    if are_there_school_related_errors
      response = {errors: {school: "can't be blank"}}
    elsif are_there_non_school_related_errors
      response = {errors: self.errors}
    else
      response = self
    end
    response
  end

  def updated_school(school_id)
    if self.subscription && self.subscription.school_subscriptions.any?
      # then they were previously in a school with a subscription, so we destroy the relationship
      UserSubscription.find_by(user_id: self.id, subscription_id: self.subscription.id).destroy
    elsif self&.subscription&.account_type == "Purchase Missing School"
      SchoolSubscription.create(school_id: school_id, subscription_id: self.subscription.id)
    end
    school = School.find(school_id)
    if school && school.subscription
      # then we let the user subscription handle everything else
      UserSubscription.create_user_sub_from_school_sub_if_they_do_not_have_that_school_sub(self.id, school.subscription.id)
    end
  end

  def is_premium?
    !!(subscription && subscription.expiration >= Date.today)
  end

  def getting_started_info
    checkbox_data = {
      completed: self.checkboxes.map(&:objective_id),
      potential: Objective.where(section: 'Getting Started')
    }
    if checkbox_data[:completed].count < checkbox_data[:potential].count
      checkbox_data
    else #checkbox data unnecessary
      false
    end
  end

  def subscription_is_expired?
    subscription && subscription.expiration < Date.today
  end

  def subscription_is_valid?
    subscription && subscription.expiration > Date.today
  end

  def teachers_activity_sessions_since_trial_start_date
    ActivitySession.where(user: self.students)
                   .where("completed_at >= ?", TRIAL_START_DATE)
  end

  def eligible_for_trial?
    premium_state == 'none'
  end

  def trial_days_remaining
    valid_subscription =   subscription && subscription.expiration > Date.today
    if valid_subscription && (subscription.is_trial?)
      (subscription.expiration - Date.today).to_i
    else
      nil
    end
  end

  def premium_updated_or_created_today?
    if subscription
      [subscription.created_at, subscription.updated_at].max == Time.zone.now.beginning_of_day
    end
  end

  def premium_state
    if subscription
      subscription.account_type == 'Teacher Trial' ? 'trial' : 'paid'
    elsif self.subscriptions.exists?
      # then they have an expired or 'locked' sub
      'locked'
    else
      'none'
    end
  end

  def is_beta_period_over?
    Date.today >= TRIAL_START_DATE
  end

  def finished_diagnostic_unit_ids
    Unit.find_by_sql("SELECT DISTINCT units.id FROM units
      JOIN classroom_activities AS ca ON ca.unit_id = units.id
      JOIN activities AS acts ON ca.activity_id = acts.id
      JOIN activity_sessions AS actsesh ON actsesh.classroom_activity_id = ca.id
      WHERE units.user_id = #{self.id}
      AND acts.activity_classification_id = 4
      AND actsesh.state = 'finished'")
  end

  def set_and_return_lessons_cache_data
    lessons_cache = get_data_for_lessons_cache
    set_lessons_cache(lessons_cache)
    lessons_cache
  end

  def set_lessons_cache(lessons_data=nil)
    if !lessons_data
      lessons_data = get_data_for_lessons_cache
    end
    $redis.set("user_id:#{self.id}_lessons_array", lessons_data.to_json)
  end

  def get_data_for_lessons_cache
    lesson_classroom_activities = []
    self.classrooms_i_teach.each do |classroom|
      classroom_activities.select{|ca| ca.activity.activity_classification_id == 6}.each{|ca| lesson_classroom_activities.push(ca.lessons_cache_info_formatter)}
    end
    lesson_classroom_activities
  end

  def classrooms_i_am_the_coteacher_for_with_a_specific_teacher(teacher_id)
    Classroom.find_by_sql("SELECT classrooms.* FROM classrooms
      JOIN classrooms_teachers AS ct_i_coteach ON ct_i_coteach.classroom_id = classrooms.id
      JOIN classrooms_teachers AS ct_of_owner ON ct_of_owner.classroom_id = classrooms.id
      WHERE ct_i_coteach.role = 'coteacher' AND ct_i_coteach.user_id = #{self.id} AND
      ct_of_owner.role = 'owner' AND ct_of_owner.user_id = #{teacher_id.to_i}")
  end

  def classrooms_i_own_that_a_specific_user_coteaches_with_me(teacher_id)
    Classroom.find_by_sql("SELECT classrooms.* FROM classrooms
      JOIN classrooms_teachers AS ct_i_own ON ct_i_own.classroom_id = classrooms.id
      JOIN classrooms_teachers AS ct_of_coteacher ON ct_of_coteacher.classroom_id = classrooms.id
      WHERE ct_i_own.role = 'owner' AND ct_i_own.user_id = #{self.id} AND
      ct_of_coteacher.role = 'coteacher' AND ct_of_coteacher.user_id = #{teacher_id.to_i}")
  end

  def classroom_ids_i_have_invited_a_specific_teacher_to_coteach(teacher_id)
    ActiveRecord::Base.connection.execute("SELECT cci.classroom_id FROM invitations
    JOIN users AS coteachers ON coteachers.email = invitations.invitee_email
    JOIN coteacher_classroom_invitations AS cci ON cci.invitation_id = invitations.id
    WHERE coteachers.id = #{teacher_id.to_i} AND invitations.inviter_id = #{self.id}").to_a.map{|res| res['classroom_id'].to_i}
  end

  def has_outstanding_coteacher_invitation?
    Invitation.exists?(invitee_email: self.email, invitation_type: Invitation::TYPES[:coteacher], archived: false)
  end

  def ids_and_names_of_affiliated_classrooms
    ActiveRecord::Base.connection.execute("
      SELECT DISTINCT(classrooms.id), classrooms.name
      FROM classrooms_teachers
      JOIN classrooms ON classrooms.id = classrooms_teachers.classroom_id AND classrooms.visible = TRUE
      WHERE classrooms_teachers.user_id = #{self.id}
      ORDER BY classrooms.name ASC;
    ").to_a
  end

  def ids_and_names_of_affiliated_students
    ActiveRecord::Base.connection.execute("
      SELECT DISTINCT(users.id), users.name, substring(users.name from (position(' ' in users.name) + 1) for (char_length(users.name))) || substring(users.name from (1) for (position(' ' in users.name))) AS sorting_name
      FROM classrooms_teachers
      JOIN classrooms ON classrooms.id = classrooms_teachers.classroom_id AND classrooms.visible = TRUE
      JOIN students_classrooms ON students_classrooms.classroom_id = classrooms.id AND students_classrooms.visible = TRUE
      JOIN users ON users.id = students_classrooms.student_id
      WHERE classrooms_teachers.user_id = #{self.id}
      ORDER BY sorting_name ASC;
    ").to_a
  end

  def ids_and_names_of_affiliated_units
    ActiveRecord::Base.connection.execute("
      SELECT DISTINCT(units.id), units.name
      FROM classrooms_teachers
      JOIN classrooms_teachers AS all_affiliated_classrooms ON all_affiliated_classrooms.classroom_id = classrooms_teachers.classroom_id
      JOIN classrooms ON classrooms.id = all_affiliated_classrooms.classroom_id AND classrooms.visible = TRUE
      JOIN units ON all_affiliated_classrooms.user_id = units.user_id AND units.visible = TRUE
      WHERE classrooms_teachers.user_id = #{self.id}
      ORDER BY units.name ASC;
    ").to_a
  end

  def referral_code
    self.referrer_user.referral_code
  end

  def referrals
    self.referrals_users.count
  end

  def teaches_student?(student_id)
    ActiveRecord::Base.connection.execute("
      SELECT 1
      FROM users
      JOIN students_classrooms
        ON users.id = students_classrooms.student_id
      JOIN classrooms_teachers
        ON students_classrooms.classroom_id = classrooms_teachers.classroom_id
        AND classrooms_teachers.user_id = #{self.id}
    ").to_a.any?
  end

  private

  def base_sql_for_teacher_classrooms(only_visible_classrooms=true)
    base = "SELECT classrooms.* from classrooms_teachers AS ct
    JOIN classrooms ON ct.classroom_id = classrooms.id #{only_visible_classrooms ? ' AND classrooms.visible = TRUE' : nil}
    WHERE ct.user_id = #{self.id}"
  end







end
