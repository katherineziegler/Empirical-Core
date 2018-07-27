class ClassroomActivitiesToUnitActivitiesAndClassroomUnitsWorker
  include Sidekiq::Worker

  def perform(unit_id)
    ClassroomActivity.unscoped.where(unit_id: unit_id).each do |ca|
      if Classroom.unscoped.find_by(id: ca.classroom_id) && ca.unit_id && ca.activity_id && ca.classroom_id
        begin
          ua = UnitActivity.find_or_create_by(
            unit_id: ca.unit_id,
            activity_id: ca.activity_id
          )
          ua.update(
            visible: ca.visible,
            due_date: ca.due_date
          ) if ua

          cu = ClassroomUnit.find_or_create_by(
            unit_id: ca.unit_id,
            classroom_id: ca.classroom_id
          )
          cu.update(
            visible: ca.visible,
            assigned_student_ids: ca.assigned_student_ids,
            assign_on_join: ca.assign_on_join
          ) if cu

          if cu && cu.id
            ca.activity_sessions.update_all(classroom_unit_id: cu.id)
          end

          if ca.activity.is_lesson? && cu && ua && cu.id && ua.id
            ClassroomUnitActivityState.find_or_create_by(
              unit_activity_id: ua.id,
              classroom_unit_id: cu.id,
              pinned: ca.pinned,
              locked: ca.locked,
              completed: ca.completed
            )
          end
        rescue Exception => e
          puts e.message
        end
      end
    end
  end

end
