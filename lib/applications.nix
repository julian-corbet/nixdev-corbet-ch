#
# The cluster catalogue: what nixdev's cluster-side tools ARE. One group, because the repository
# genuinely runs one kind of thing here -- a developer's tool with a web face -- and inventing
# groups a domain does not have is how a model starts lying.
#
# WHAT BELONGS HERE, and it is not "anything a developer opens". The test this repository already
# applies to its package side applies here too: the subject is the developer's own toolbox. A
# snippet manager and a data-transform workbench are tools a developer reaches for; a wiki is not,
# even though developers read wikis, and a chart renderer is not, even though developers embed
# charts. Those have owners of their own.
#
# WHAT IS KNOWLEDGE AND WHAT IS A VALUE. Everything in this file is true of the software wherever
# anyone runs it: the port it listens on, the directory it writes, which probes it warrants and
# what they ask for, which environment variables it reads secret material from, what it can be
# locked down to. Nothing here names an address, a node, a hostname, a namespace, a Secret or a
# credential -- those are one deployment's facts and they arrive from the consumer. The split is
# enforced rather than trusted: `state` here is the path INSIDE the container and only a
# declaration can say what backs it; `credentials` here is a list of VARIABLE NAMES and only a
# declaration can say which Secret delivers them.
#
# THE THREE SPLIT FIELDS, because each one is half a statement and the halves live in different
# repositories:
#
#   state       here: WHERE inside the container       declaration: WHAT BACKS IT
#   probes      here: WHICH probes, WHAT they ask      declaration: THIS cluster's budget override
#   credentials here: WHICH VARIABLES carry secrets    declaration: WHICH SECRET delivers them
#   hardening   here: what the software TOLERATES      declaration: whether to STAMP it (`harden`)
{}:
{
  applications = {
    bytestash = {
      image = "ghcr.io/jordan-dalby/bytestash";
      ports.http = 5000;
      primaryPort = "http";

      # ONE DIRECTORY, holding an opaque SQLite database. That single fact decides the workload's
      # whole shape: a database file is a SINGLE-WRITER resource, so two pods sharing it is two
      # writers on one file, so the deployment cannot roll -- the old pod must be gone before the
      # new one starts. A consumer never states that; declaring state is what states it.
      state.data = "/data/snippets";

      env = { };
      args = [ ];

      # THE VARIABLES IT READS SECRET MATERIAL FROM. Names, never values, and that is exactly what
      # makes them knowledge: which variable this image looks in is a property of the image, the
      # same way the port is. WHICH Secret carries them, and under which keys, is one deployment's
      # fact and cannot be written here.
      #
      # `JWT_SECRET` signs the sessions it hands out. `OIDC_CLIENT_SECRET` authenticates it to the
      # identity provider when the OIDC switches in `env` are on -- which is a deployment's
      # decision, so the variable is catalogued and the decision is not.
      credentials = [ "JWT_SECRET" "OIDC_CLIENT_SECRET" ];

      # WHAT IT CAN BE LOCKED DOWN TO, as classes rather than numbers. Every line here is a claim
      # about the software: it is a Node process serving HTTP on an unprivileged port, so it needs
      # no Linux capability, never has to regain privilege, and runs unbothered under the default
      # seccomp profile. None of that changes with the cluster, which is why it is knowledge --
      # while WHETHER a given deployment stamps the claims onto its pod is `harden`, over there.
      #
      # `rootFilesystem` is null on purpose and is not a shrug: it records that nobody has
      # established whether this image can run with its root filesystem read-only, and a null
      # renders NO field at all rather than a `false` that would look like a finding. Turning it
      # into "writable" or "read-only" means somebody ran it and looked.
      hardening = {
        capabilities = "none";
        privilegeEscalation = "never";
        seccomp = "RuntimeDefault";
        rootFilesystem = null;
      };

      # WHICH PROBES IT WARRANTS AND WHAT THEY ASK. Everything served is behind one HTTP front, so
      # "/" is both the cheapest and the most honest endpoint: if it answers, the app works.
      #
      # `timeoutSeconds` is here rather than in a declaration because it is a statement about how
      # fast THIS SOFTWARE answers, not about how much patience a cluster has: a Node process with
      # an open SQLite database can take whole seconds to reply under load, and one second would
      # call that a failure anywhere.
      #
      # IT WARRANTS A STARTUP PROBE, which the workbench beside it does not. Node boots, then the
      # database file is opened and migrated, and only then does anything answer -- so without a
      # startup probe the liveness probe reads a slow first boot as a hang and restarts the pod
      # into the same slow boot. The numbers below are the software's own patience; a cluster that
      # wakes it from zero and holds a request open while it boots has a longer budget than this
      # and says so in its declaration.
      probes = {
        readiness = { path = "/"; periodSeconds = 10; failureThreshold = 6; timeoutSeconds = 5; };
        liveness = { path = "/"; periodSeconds = 20; failureThreshold = 6; timeoutSeconds = 5; };
        startup = { path = "/"; periodSeconds = 5; failureThreshold = 24; timeoutSeconds = 5; };
      };

      note = ''
        A snippet manager: a personal store of code fragments with syntax highlighting, search and
        sharing, so the useful twenty lines from six months ago are findable instead of being
        rewritten.

        IT AUTHENTICATES PEOPLE, and that is the field that makes it different from the workbench
        beside it. It can run its own accounts or defer to an OIDC provider, and which one is a
        deployment's decision rather than the software's -- so the switches are declarable and
        their VALUES are not here. An issuer URL and a client id identify one installation's
        identity provider; they are not credentials, and they are still not knowledge. The two
        variables that ARE credentials are catalogued above by NAME, because which variable an
        image reads is the image's property and what goes in it is nobody's business here.

        THE DATABASE IS THE CONSTRAINT, not the size. This is a small application by every other
        measure, and it still cannot roll, cannot scale past one replica and cannot share its
        directory -- because SQLite is single-writer and none of those follow from how much
        traffic it takes.

        IT IS WORTH SLEEPING. A snippet store is opened deliberately, a few times a day, by one
        person; between those moments it does nothing but hold a file. Nothing in it fires on a
        timer and nothing watches a directory, so at zero replicas there is no work that fails to
        happen -- which is the actual test for whether idling is safe, rather than whether the
        workload is small.
      '';
    };

    cyberchef = {
      image = "ghcr.io/gchq/cyberchef";
      ports.http = 8080;
      primaryPort = "http";

      # NOTHING. Stated as an empty set rather than left out: the assertion that a declaration
      # backs every directory the catalogue says is written reads this attribute, so omitting it
      # throws where it should assert "backs none".
      state = { };

      env = { };
      args = [ ];

      # NO CREDENTIALS AT ALL, and stated the same way and for the same reason: the assertion that
      # a declaration names a Secret exactly when the software reads one reads this list, and an
      # empty list is what makes "this workload may not name a Secret" checkable rather than
      # assumed. A static bundle has nobody to authenticate to.
      credentials = [ ];

      # An unprivileged nginx serving files. Same three classes as the snippet manager, for the
      # same reasons and with even less room for doubt -- it is the port that gives it away, see
      # the note.
      hardening = {
        capabilities = "none";
        privilegeEscalation = "never";
        seccomp = "RuntimeDefault";
        rootFilesystem = null;
      };

      # Everything is served statically, so "/" is the whole health question, and one second is
      # long enough for a file server to hand back an index -- which is why `timeoutSeconds` here
      # is a quarter of the snippet manager's and neither number is a cluster's choice.
      #
      # NO STARTUP PROBE, and its absence is a fact rather than an omission: nginx binds and
      # serves immediately, so there is no slow first boot for a startup probe to cover, and a
      # declaration that tries to budget one for this app is refused rather than ignored.
      probes = {
        readiness = { path = "/"; periodSeconds = 10; failureThreshold = 6; timeoutSeconds = 1; };
        liveness = { path = "/"; periodSeconds = 20; failureThreshold = 6; timeoutSeconds = 1; };
      };

      note = ''
        A data-transform workbench: decode, encode, decrypt, parse and convert, composed as a
        pipeline of small operations. The tool a developer opens when something is base64 inside
        gzip inside a URL parameter and the answer is faster to build than to reason about.

        IT RUNS ENTIRELY IN THE BROWSER, and that single fact is the whole reason it is easy to
        run. What is served is a static bundle; every transform happens on the reader's machine.
        So the container is an unremarkable web server with no backend, nothing to store, no
        credential to hold, and no way for one person's work to reach another's -- which is also
        why it is the safe first thing to migrate anywhere.

        THE PORT IS THE ONE SURPRISE. Its nginx runs unprivileged and therefore binds 8080 rather
        than 80. That is not a preference to be normalised: a workload that cannot bind a
        privileged port is a workload that does not need to run as root, and the port is the
        visible half of that. It is also why the hardening classes above are not a guess.

        WHETHER IT SLEEPS IS NOT THIS FILE'S CALL. Nothing about a static bundle argues against
        idling -- it starts instantly and loses nothing. But a wake front is a piece of one
        cluster's routing, and whether that path is trustworthy is something only the deployment
        knows; this repository has no way to see a broken interceptor. So the class is declarable
        and the default is not chosen here.
      '';
    };
  };
}
