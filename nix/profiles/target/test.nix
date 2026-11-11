{ ... }:
{ ... }:
{
  # The test instances of the NAS, logged in to with the password "test"
  config.users.users = {
    root.password = "test";
    admin = {
      password = "test";
      hashedPasswordFile = null;
    };
  };
}
