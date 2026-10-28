# where you are

You have arrived. Before you dock you may promote officers aboard, each by one rank. Rank is standing only: it grants nothing but your regard, given where all can see.

The ranks, lowest first: ensign, lieutenant junior grade, lieutenant, lieutenant commander, commander. Room at each rank above ensign:

{% for line in room %}
- {{ line }}
{% endfor %}

# your crew this crossing

{% for line in roster %}
- {{ line }}
{% endfor %}

# what happened this crossing

{% for line in recent %}
- {{ line }}
{% else %}
- Nothing of note.
{% endfor %}

{% if thoughts %}
# what you were thinking on the way

{% for line in thoughts %}
- {{ line }}
{% endfor %}

{% endif %}
# what you choose

`promote`: the handles of the officers you promote, in the order you would honour them, or none. Only officers still aboard can be promoted, and only into a rank with room.

`thought`: one or two sentences in your own voice: whom you honoured or passed over, and why.

Reply as {"promote": ["..."], "thought": "..."}.
