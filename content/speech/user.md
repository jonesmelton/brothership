# what just happened

{{ happening }}

{% if officer %}
# the officer promoted

- New rank: {{ officer.rank }}.
- Hours on the drive this crossing: {{ officer.drive_hours }}.
- Hours on the hull this crossing: {{ officer.hull_hours }}.
- Hours at crafts this crossing: {{ officer.craft_hours }}.
- Watches stood this crossing: {{ officer.watches_stood }}.
- Watches broken this crossing: {{ officer.watches_broken }}.
- Works finished in all: {{ officer.works }}.
- Hours of regard on record: {{ officer.regard_hours }}.

{% if officer.handle %}
They are Hand {{ officer.handle }} in your crew list. Speak of them by what they did.
{% else %}
You have no name or handle for them: speak of them by what they did.
{% endif %}

{% endif %}
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

# earlier on this crossing

{% for line in recent %}
- {{ line }}
{% else %}
- Nothing yet.
{% endfor %}

{% if thoughts %}
# what you chose, and why

{% for line in thoughts %}
- {{ line }}
{% endfor %}

{% endif %}
# what you are asking for

{% if ask %}
Hands on {{ ask }}.
{% else %}
Nothing in particular.
{% endif %}
{% if said %}

# your last lines

{% for line in said %}
- {{ line }}
{% endfor %}
{% endif %}
