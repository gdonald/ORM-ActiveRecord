use v6.c;
use lib 'lib';
use ActiveRecord;

class Page {...}

class User is ActiveRecord {
    
    submethod BUILD {
        self.has-many: pages => class => Page;
    }

    method fullname {
	self.fname ~ ' ' ~ self.lname;
    }
}

class Page is ActiveRecord {
    
    submethod BUILD {
        self.belongs-to: user => class => User;
    }
}

sub MAIN {
    my User $user = User.find(1);
    say "User Full Name: {$user.fullname}";

    my Page $page = $user.pages.first;
    say "Page Name: {$page.name}";
    say "User First Name via page: {$page.user.fname}";
}
