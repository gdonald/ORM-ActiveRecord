use ORM::ActiveRecord::Model;

unit module Validation::Format;

class Contact is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence, format => { with => /:i ^<[\w]>+ '@' <[\w]>+ '.' <[\w]>+$/ } }
  }
}

GLOBAL::<Contact> := Contact;
