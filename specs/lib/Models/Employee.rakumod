use ORM::ActiveRecord::Model;

unit module Models::Employee;

class Employee is Model is export {
  submethod BUILD {
    self.belongs-to: manager     => %(class-name => 'Employee', optional => True);
    self.has-many:   subordinates => %(class-name => 'Employee', foreign-key => 'manager_id');
  }
}

GLOBAL::<Employee> := Employee;
