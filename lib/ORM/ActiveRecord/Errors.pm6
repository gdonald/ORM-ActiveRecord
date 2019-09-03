
use ORM::ActiveRecord::Error;

class Errors {
  has @.errors of Error;

  method push(Error $error) {
    @!errors.push($error);
  }

  submethod FALLBACK($name, *@rest) {
    @!errors.map({ .message if .field eq $name });
  }
}
