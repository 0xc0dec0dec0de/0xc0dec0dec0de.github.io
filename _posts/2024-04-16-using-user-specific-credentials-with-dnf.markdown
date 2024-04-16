---
layout: post
title:  "Using user-specific credentials with DNF and JFrog Artifactory"
date:   2024-04-16 16:30:00 -0400
categories:
  - 
tags:
  - dnf
  - package-management
  - change-management
  - access-control
  - jfrog-artifactory
---

Did you know that [you can pass environment values][dnf-vars] into `dnf` and it will use them in your repo files?

I very recently learned this.
The thing that it made me realize is that I could use it to pass user-specific credentials!
Before seeing this I had been tossing around the idea of writing a custom plugin to get the calling user's credentials and using them to connect to our JFrog Artifactory instance.
So this is easier and involves less custom code.
That's always good.

Alright, so, so far we can defer passing credentials to `dnf` until runtime instead of having a shared set of credentials that are world-readable on your machine!
I know, I know.
If it's *your* machine, it doesn't matter, but if you're sharing a box with some colleagues...

Anyway, we can make our repo file:

{:codelabel="ini" filename="example.repo"}
```ini
[example]
baseurl = https://artifactory.example.org/fedora/$releasever/$basearch/
description = Example DNF Repo
username = $ARTIFACTORY_EXAMPLE_ORG_USER
password = $ARTIFACTORY_EXAMPLE_ORG_PASSWORD
# Important to add this next line unless you want to make people angry.
skip_if_unavailable = 1
```

So, now we can provide our own username and password, like so:

```sh
DNF_VAR_ARTIFACTORY_EXAMPLE_ORG_USER=c0dec0dec0de \
DNF_VAR_ARTIFACTORY_EXAMPLE_ORG_PASSWORD=hunter2 \
sudo dnf install -y example-pkg
```

That is not my actual password.
Seriously.
Also, not my real username and not a real JFrog Artifactory instance.

Alright, maybe this isn't very convenient.
Also, at the time of this writing, the version of `dnf` available in RHEL8 doesn't support shell-like parameter expansion despite any insistence of the documentation.
So, no ability to provide default values to fall back on.
Maybe in a few more months that functionality will get back-ported.

Whatever, let's make this usable.
JFrog's CLI stores your login credentials in plaintext in your home directory.
That's not great, but NFS noroot and restrictive permissions *should* make that reasonably okay.
Strongly prefer using an API key over your password though -- particularly if your JFrog instance is set up to federate identities from your corporate network.
It's a JSON file, so that means we're going to use [`jq`][jq] to pull data out.

{:codelabel="Bash" filename="/usr/local/bin/dnf"}
{% highlight shell lineos %}
{% include dnf_wrapper  %}
{% endhighlight %}

Neat.
Stick that in `/usr/local/bin` and we're cooking.

Oh.
Except that I sometimes use Ansible for configuring systems and I don't want to have hard-coded or encrypted credentials in my plays.
Let's make a play that we can prepend onto our playbook.

{:codelabel="Ansible YAML" filename="extract_credentials.yaml"}
{% highlight yaml %}
{% include extract_credentials.yaml %}
{% endhighlight %}

Okay, that's kinda gross.
But, it's also something you don't have to actually look at.
Just prepend it to your plays and now you can pass {% raw %}`{{ dnf_vars }}`{% endraw %} as the `environment` for all your `ansible.builtin.package` tasks.

{:codelabel="Ansible YAML" filename="playbook.yaml"}
{% highlight yaml %}
{% raw %}
---
- name: Extract JFrog Artifactory credentials
  hosts:
    - all
  tasks:
    - name: Extract JFrog Artifactory credentials
      include_tasks: extract_credentials.yaml
      vars:
        required: true

- hosts:
    - all
  environment: "{{ dnf_vars }}"
  roles:
    - your_role_here
{% endraw %}
{% endhighlight %}

Keen-eyed readers may have noticed that the `extract_credentials.yaml` play also created a `credentials` dictionary keyed by hostname.
If you need to pull artifacts from Artifactory that aren't governed by DNF, you can pass the same credentials through `ansible.builtin.get_url`:

{:codelabel="Ansible YAML"}
{% highlight yaml %}
{% raw %}
---
- name: Get a tarball
  ansible.builtin.get_url:
    url: "{{ item }}"
    url_username: "{{ credentials[item | urlsplit('hostname')].username | default(omit) }}"
    url_password: "{{ credentials[item | urlsplit('hostname')].password | default(omit) }}"
  loop:
    - "https://artifactory.example.org/github/ansible/ansible/archive/refs/tags/v2.16.6.tar.gz"
{% endraw %}
{% endhighlight %}

Let me know on [Mastodon][mastodon] what you think and if this helped you.

[dnf-vars]: https://dnf.readthedocs.io/en/latest/conf_ref.html#repo-variables
[jq]: https://jqlang.github.io/jq
[mastodon]: https://hachyderm.io/@c0dec0dec0de
