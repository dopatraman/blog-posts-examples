Title: Easy Elixir Release Distributions with Ansible

In [my last post](), I described how to generate a platform-specific Elixir
release. Now that you have that, the only thing left is to put it on the
worldwide web.

To follow along with this post, you'll need a few things:
  1. An IP address for a remote machine you want to deploy your application to
  2. A public RSA key placed on that remote machine
  3. Ansible (on your local machine)

While all three of these are a bit out of the scope of this tutorial to cover in
depth, I can try to point you in the right directions [here](), and [here]().

## The Plan
To consider our deployment automation a success, it needs to be able to do the
following:
  1. Copy our local release artifact to a remote machine
  2. Deploy any auxillary services (like a database instance) and make them
    accessible to our release application
  3. Ensure that our deployment is idempotent, because we'll be using it to ship
    code to the box over and over again.

### Simple is best?
One way to accomplish this, the easiest way, is through plain ol' SSH. SCP is a
time-tested tool that allows for uploading files through a secure tunnel.
Assuming you've placed the public key of your RSA key-pair on your remote
machine, you should be able to do the following:
```
$ scp local/path/to/release/folder username@host_ip:remote/path/to/release/folder
$ ssh username@host_ip
<... authenticate ...>
$ local/path/to/release/folder daemon
```
These commands takes care of goal 1, but they ignore 2 and 3 completely. Our app
does not have a database available to it. There also isn't much we can re-use, because to
redeploy, we'll need to SSH back into the box, stop the application, delete the
release, and then re-copy everything from the our local machine. 

While simple is good, too simple can be a headache. To follow the plan, we'll
need to automate the configuration of the remote machine itself.

### Configuration Management
To ensure that our application behaves the way we expect it to, we need to
control the environment it runs in. We'll need to build it from scratch,
provision and seed a database, copy the release, run it, and test for uptime.
Each one of those commands needs to be idempotent because when the time comes to
ship a new build, we'll have to tear everything down and do it all again. And
then again, and again after that.

Let's get started.

## Enter Ansible
Add the IP of your target machine to the `/etc/ansible/hosts` file.

We can use Ansible to run commands on our remote machine. The Ansible core team
has developed all kinds of useful goodies, and that ecosystem will come in handy
for us. As a bonus, many of these core modules have idempotence baked in.

### System setup
Let's use the [apt]() module to setup our machine.
```
# system-setup.yml
---
- name: install system packages
  apt:
    update_cache: yes
    state: present
    name:
      - gcc
      - g++
      - curl
      - wget
      - unzip
      - git
      - python-dev
      - python-apt
      - make
      - automake
      - autoconf
      - libreadline-dev
      - libncurses-dev
      - libssl-dev
      - libyaml-dev
      - libxslt-dev
      - libffi-dev
      - libtool
      - unixodbc-dev
```
Let's also install pip, since we'll need it for the next step. Ansible core has
a handy module called [python-pip]() that we can use just for this:
```
# system-setup.yml
- name: install pip
  apt:
    update_cache: yes
    state: present
    name: python-pip
```

### The Postgres Instance
Now that our machine has been provisioned with the basics, we need to install Postgres. The `apt`
module will do this nicely:
```
# postgres.yml
---
- name: install postgres + postgres packages
  apt:
    update_cache: yes
    state: present
    name:
      - postgresql
      - postgresql-contrib
      - libpq-dev
```
_(You can include these Postgres dependencies as a part of the first apt call if
you want, but I chose to separate them because I found it easier to follow.)_

Now, to interact with our Postgres instance, we'll need a driver. Since Ansible
is written in Python, it works with Python libraries best. Let's use the
`psycopg2` package and install it with pip:
```
# postgres.yml
- name: install psycopg2
  pip:
    name: psycopg2
```

#### Credentials
Next, we'll need to securely store sensitive credentials (in this case,
our database username and password).

To do that, we're going to use a [plugin]() called [lookup](). To use the looked-up value later on, we need to store it and make it available
to rest of our pipeline. Ansible calls these stored values "facts" -- to create
one, use the [set_fact]() module:
```
# postgres-facts.yml
- when: "database_name is not defined"
  name: "compute database name"
  set_fact:
    database_name: "{{ lookup('env', 'DATABASE_NAME') }}"

- name: set database host
  set_fact:
    database_host: "{{ lookup('env', 'DATABASE_HOST') }}"

- name: create or get postgres password
  set_fact:
    database_password: "{{ lookup('env', 'DATABASE_PASSWORD') }}"

- name: set database user
  set_fact:
    database_user: "{{ lookup('env', 'DATABASE_USER') }}"

```
(We're looking for values in [environment]() variables, so make sure they are
set.)

##### N.B.
This approach could get annoying if you plan on deploying from more than one
machine (since you might not always have the same environment). [Ansible
Vault]() is an alternative, but it's out of this post's scope.

#### User and Database
Now that we have an instance and credentials, we can create a user and associate
it with an actual database.

Two modules will come in handy here, [postgresql_user]() and [postgresql_db]():
```
# postgres.yml
- name: create postgres user
  postgresql_user:
    name: "{{database_user}}"             # 1
    password: "{{database_password}}"     # 1
    role_attr_flags: CREATEDB,SUPERUSER   # 2
    state: present
  become_user: postgres                   # 3
  become: yes                             # 4

- name: create database
  postgresql_db:
    name: "{{database_name}}"             # 1
    encoding: "UTF-8"
  become_user: postgres                   # 3
  become: yes                             # 4

```

Let's break down what's going on here. The `postgresql_user` is doing a couple
of things:
  1. Specifying credentials (these keys were set as facts in the previous step)
  2. Assigning roles to the new user (in this case, the Superuser and Creation
     roles)
  3. Declaring a persona on the target machine (every Postgres instance comes
     with a default "postgres" user) to assume and
  4. Assuming that persona

Next we actually create the data base, using #3 and #4 from above. Together,
these two tasks allow us to access the database from our application, provided
we do so using the right username and password.

### "Deployment"
Next, we need to move our artifact to our box:
```
# deploy-release.yml
---
# 1
- name: check to see if release archive exists locally
  stat:
    path: "{{ release_archive_path }}"
  register: release_st
  delegate_to: 127.0.0.1

# 2
- name: fail if no local release
  fail:
    msg: "Local release tarball not found. Copy it to {{ release_archive_path }}."
  when: not release_st.stat.exists

# 3
- name: clean remote release directory
  file:
    path: "{{remote_release_dir}}"
    state: absent

- name: create remote release directory
  file:
    path: "{{remote_release_dir}}"
    state: directory

# 4
- name: unarchive release on remote server
  unarchive:
    src: "{{release_archive_path}}"
    dest: "{{remote_release_dir}}"

# 5
- name: check to see if release artifact exists remotely
  stat:
    path: "{{remote_release_artifact_path}}"
  register: remote_release_artifact_st

# 6
- name: echo end
  debug:
    var: remote_release_artifact_st.stat.exists

```

Here's the breakdown:
1. We check to see if the release was properly created _locally_, and store its
   state in a variable.
2. If the above check fails, stop everything.
3. If it passes, clean out the remote release, and recreate the directory.
4. We copy and unarchive the release and then
5. Check to see that it was properly copied
6. Finally we echo the status of the remote release artifact.

If Step 6 passes, you've successfully deployed your app! Now we can do one of
two things: apply a migration, or start it up.

#### Optional: Migrations
Once we have the database up and running and an application artifact to play
with, we have the option of applying migrations. Have a look at this playbook:
```
# run-migrations.yml
---

# 1
- name: check if postgres is running
  command: "/etc/init.d/postgresql status"
  register: postgres_st

# 2
- fail:
    msg: "Postgres is not running"
  when: postgres_st.stderr != "" or postgres_st.failed != false

# 3
- name: check to see if release artifact exists remotely
  stat:
    path: "{{remote_release_artifact_path}}"
  register: remote_release_artifact_st

# 4
- fail:
    msg: "No remote release artifact"
  when: not remote_release_artifact_st.stat.exists

# 5
- name: run migrations on remote server
  command: "{{remote_release_artifact_path}} eval 'ReleaseTasks.migrate'"
  when: remote_release_artifact_st.stat.exists

```
Here's what's going on:
  1. First off, we check if Postgres is running, and store its "up" status in a
     variable.
  2. If postgres is not running, we fail out.
  3. We check to see if the release artifact exists.
  4. Fail if the artifact does not exist for some reason.
  5. When it does, we run a command. 
    a. This command references a
      module that was packaged into my release. The `ReleaseTasks` module is the
      following:
      ```
defmodule ReleaseTasks do
  def migrate do
    {:ok, _} = Application.ensure_all_started(:api)

    Ecto.Migrator.run(
      Api.Repo,
      path("priv/repo/migrations"),
      :up,
      all: true
    )

    # Close process
    :init.stop()
  end
end
      ```
    b. Keep in mind this module assumes the use of Ecto. If you aren't using Ecto, feel free to replace this code with another script that runs your migrations.

### Startup
Once our database, artifact, and possible migrations are good to go, we can
start our application on our box:
```
# up.yml
---

# 1
- name: check to see if release artifact exists remotely
  stat:
    path: "{{remote_release_artifact_path}}"
  register: remote_release_artifact_st

# 2
- name: start remote server
  command: "{{remote_release_artifact_path}} daemon"
  when: remote_release_artifact_st.stat.exists
  register: foo

# 3
- name: echo end
  debug:
    var: foo
```
Here's what's happening. Do you notice a pattern?
  1. We check to make sure the release artifact exists.
  2. We start it as a [background process](), and register the output as a varible.
  3. Then, dump the output to stdout.

Admittedly this last part is not as elegant as I'd like it to be, but it is a
good way of visualizing what's going on as the box is running your program. I'm
open to suggestions on better ways to do this!

Now, if you get to Step 3 and see a successful output in your console, your
application is officially running on the internet!

### Teardown
This workflow is a barebones deployment pipeline -- really the bare minimum you
need to put your release onto a box and run it. That means that should you ever
need to re-deploy, and you will, you will first need to stop your application.
The teardown could be as follows:
```
# down.yml
---

# 1
- name: check to see if release artifact exists remotely
  stat:
    path: "{{remote_release_artifact_path}}"
  register: remote_release_artifact_st

# 2
- name: stop remote server
  command: "{{remote_release_artifact_path}} stop"
  when: remote_release_artifact_st.stat.exists
  register: stop_cmd

# 3
- name: clean remote release directory
  file:
    path: "{{remote_release_dir}}"
    state: absent

# 4
- name: echo end
  debug:
    var: stop_cmd

```
Classic breakdown:
1. We check to see if the release artifact exists on our box.
2. If so, we run the [stop command]() on the release and store its output into a variable.
3. We clean out the release directory.
4. We dump the stop command output to stdout.

If Step 4 is successful, you've successfully torn everything down, made the
machine ready for a future deployment.

#### A Note on Repetition and Idempotence
You probably noticed that these playbooks repeat many of the same commands. The
reason for that is that we want each of our playbooks to be _idempotent_. In
short, we want to be able to run each of our tasks N number of times without any
adverse effects. That means that, ideally, each task is self-contained. That's
why we check the same properties and set the same facts. In the case of our
deployment playbook, we want to clean out an existing artifact directory so
that each time we deploy, the same exact thing happens. No side effects means
your process is predictable. And predictability means fewer bugs. Infrastructure
can be complex enough on its own -- if we can reduce complexity in the code we
write, we will be all the better for it.

## Putting it All Together
### The Facts
At this point, you should have 6 playbooks:
  1. System Setup
  2. Database Creation
  3. Deployment
  4. Migrations
  5. Startup
  6. Teardown

A lot of these rely on the same system facts, namely:
  - release artifact directory
  - release artifact path

We can put all of these facts into a file that will be available to every
module:
```
# project-facts.yml
---
- name: set app name
  set_fact:
    app_name: api

- name: set app version
  set_fact:
    app_version: "0.1.0"

- name: set credentials directory path
  set_fact:
    credentials_dir: "~/credentials/"

- name: set release name
  set_fact:
    release_name: "{{app_name}}-{{app_version}}"

- name: set release directory name
  set_fact:
    release_dir: "../rel/artifacts/"

- name: set release archive path
  set_fact:
    release_archive_path: "{{release_dir}}{{release_name}}.tar.gz"

- name: set remote release directory
  set_fact:
    remote_release_dir: "~/rel/artifacts/"

- name: set remote release archive path
  set_fact:
    remote_release_archive_path: "{{remote_release_dir}}{{release_name}}.tar.gz"

- name: set remote release artifact path
  set_fact:
    remote_release_artifact_path: "{{remote_release_dir}}opt/build/_build/prod/rel/api/bin/api"

```
If we really want to turn up the dial on efficiency, we can do the same for
Postgres facts:
```
# postgres-facts.yml
---
- when: "database_name is not defined"
  name: "compute database name"
  set_fact:
    database_name: "{{ lookup('env', 'DATABASE_NAME') }}"

- name: set database host
  set_fact:
    database_host: "{{ lookup('env', 'DATABASE_HOST') }}"

- name: create or get postgres password
  set_fact:
    database_password: "{{ lookup('env', 'DATABASE_PASSWORD') }}"

- name: set database user
  set_fact:
    database_user: "{{ lookup('env', 'DATABASE_USER') }}"

```
And reference them before each playbook.

### Directory Structure
Now that you have your facts files, you can simplify the rest of your playbooks
into the following structure:
```
~/project/deploy/
--- facts/
---- project-facts.yml
---- postgres-facts.yml
--- tasks/
---- system-setup.yml
---- postgres.yml
---- deploy-release.yml
---- run-migrations.yml
---- up.yml
---- down.yml
-- create-db.yml
-- deploy.yml
-- migrations.yml
-- startup.yml
-- teardown.yml
```
Each of the playbooks in the `deploy/` directory references a facts file as
well as a task.

It might take looking at actual code for this to gel. Feel free to browse the
[repo]() to see what the files themselves look like.

### Mix Aliases: Mask the Ugliness
Each time you deploy, your workflow will likely look something like this:
  1. Deploy
  2. Run Migrations
  3. Start up

Ansible ships with a tool called `ansible-playbook` that you can use to run
these commands individually:
```
$ ansible-playbook deploy/deploy.yml
$ ansible-playbook deploy/migrations.yml
$ ansible-playbook deploy/startup.yml
```
But... that's a lot of typing isn't it? Why not hide the long commands with a
mix alias?

Create two shell scripts:
```
#! /usr/bin/env bash
$ ansible-playbook deploy/deploy.yml
```
and
```
#! /usr/bin/env bash
$ ansible-playbook deploy/startup.yml
```
Make them executable with `chmod +x`.

Then, add this to your `mix.exs` file:
```
defp aliases do
    [
      deploy: ["cmd ./path/to/deploy_script"],
      up: ["cmd ./path/to/startup_script"],
      down: ["cmd ./path/to/teardown_script"]
    ]
  end
```
Once you have those aliases, deploying your app is as simple as:
```
$ mix deploy
$ mix up

# For tear down...
$ mix down
```
Lo, and behold, with two commands, you have made your app available to the world!

Thanks for reading. Peruse the code behind this post [here](), and feel free to
email me with questions/suggestions as prakash@carbonfive.com

### Module Glossary
Here's a quick reference for all the modules we used:
to be using.
- set_fact
- apt
- pip
- lookup (actually this is a [plugin]() and not a module)
- stat
- file
- unarchive
- postgresql_user
- postgresql_db

