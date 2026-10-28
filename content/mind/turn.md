# where you are

{% for line in readout %}
{{ line }}
{% endfor %}

# your crew this crossing

{% for line in roster %}
- {{ line }}
{% else %}
- Nobody has taken a post yet.
{% endfor %}

# what has happened this crossing

{% for line in recent %}
- {{ line }}
{% else %}
- Nothing yet.
{% endfor %}

{% if thoughts %}
# what you were thinking before

{% for line in thoughts %}
- {{ line }}
{% endfor %}

{% endif %}
# what you choose now

`ask`: what you ask your crew for, until something next happens.

- "drive": hands on the drive burn harder and bring everyone to port sooner, and wear the hull faster.{% if not firing %} You are coasting, so the drive does nothing until the approach.{% endif %}
- "hull": hands on the hull mend wear. A worn hull lowers the speed the drive can reach.
- "crafts": hands go to their own work. Engineers build your refits; artists make works that earn them standing and bring you recruits at port.
- "nothing": you ask for nothing in particular.

You are asking for {{ ask }} now.

`refit`: what your engineers build next. They can choose otherwise.

{% for r in refits %}
- "{{ r.name }}": {{ r.effect }}.
{% endfor %}
- "none": nothing.

They are building {{ refit }} now.

`thought`: one or two sentences in your own voice: why, and what you feel about this moment and this crew.

Reply as {"ask": "...", "refit": "...", "thought": "..."}.
