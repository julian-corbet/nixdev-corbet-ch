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
# anyone runs it: the port it listens on, the directory it writes, how patient a probe has to be,
# what it does when nobody is looking. Nothing here names an address, a node, a hostname, a
# namespace or a secret's contents -- those are one deployment's facts and they arrive from the
# consumer. The split is enforced rather than trusted: `state` here is the path INSIDE the
# container, and what backs it can only be supplied by a declaration.
{ }:
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

      readiness = {
        path = "/";
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 6;
      };

      note = ''
        A snippet manager: a personal store of code fragments with syntax highlighting, search and
        sharing, so the useful twenty lines from six months ago are findable instead of being
        rewritten.

        IT AUTHENTICATES PEOPLE, and that is the field that makes it different from the workbench
        beside it. It can run its own accounts or defer to an OIDC provider, and which one is a
        deployment's decision rather than the software's -- so the switches are declarable and
        their VALUES are not here. An issuer URL and a client id identify one installation's
        identity provider; they are not credentials, and they are still not knowledge.

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

      readiness = {
        path = "/";
        periodSeconds = 10;
        failureThreshold = 6;
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
        visible half of that.

        WHETHER IT SLEEPS IS NOT THIS FILE'S CALL. Nothing about a static bundle argues against
        idling -- it starts instantly and loses nothing. But a wake front is a piece of one
        cluster's routing, and whether that path is trustworthy is something only the deployment
        knows; this repository has no way to see a broken interceptor. So the class is declarable
        and the default is not chosen here.
      '';
    };
  };
}
