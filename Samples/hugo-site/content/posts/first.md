+++
title = 'First Post'
date = 2026-11-21T10:00:00+03:00
draft = false
+++

# First Post

Links in this site use the **relref** shortcode:

- [The second post]({{< relref "/posts/second" >}})
- [A section of it]({{< relref "/posts/second#details" >}})
- [About]({{< relref "/about" >}})

A page that doesn't exist yet: [future post]({{< relref "/posts/future" >}}) (⌘-click to create it).

A [[wiki link]] would not build in Hugo, so it is marked.

{{< figure src="/images/logo.png" width="240" alt="Logo" >}}

{{< note >}}
A shortcode block.
{{< /note >}}
