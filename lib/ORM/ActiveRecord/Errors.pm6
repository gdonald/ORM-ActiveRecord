
use ORM::ActiveRecord::Error;

class Errors {
  has @.errors of Error;

  method push(Error:D $error) {
    @!errors.push($error);
  }

  submethod FALLBACK(Str:D $name, *@rest) {
    @!errors.map({ .message if .field eq $name });
  }
}
