# static builds cannot dlsym(NULL): look the built-in link types up in a table instead
undef $/; $_ = <STDIN>;
s{(struct link_util \*get_link_kind\(const char \*id\)\n\{)}{
extern struct link_util veth_link_util, bridge_link_util, bridge_slave_link_util, dummy_link_util, vlan_link_util;
static struct { const char *id; struct link_util *l; } dib_static_kinds[] = {
	{"veth", &veth_link_util}, {"bridge", &bridge_link_util}, {"bridge_slave", &bridge_slave_link_util},
	{"dummy", &dummy_link_util}, {"vlan", &vlan_link_util}, {0, 0}
};
$1
	for (int i = 0; dib_static_kinds[i].id; i++)
		if (strcmp(dib_static_kinds[i].id, id) == 0) {
			struct link_util *s = dib_static_kinds[i].l;
			if (!s->next && s != linkutil_list) { s->next = linkutil_list; linkutil_list = s; }
			return s;
		}
}; print;
