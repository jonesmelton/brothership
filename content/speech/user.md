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

You have no name or handle for them: speak of them by what they did.

{% endif %}
# where you are

{% for line in readout %}
{{ line }}
{% endfor %}

# earlier on this crossing

{% for line in recent %}
- {{ line }}
{% else %}
- Nothing yet.
{% endfor %}

# what you are asking for

{% if ask %}
Hands on {{ ask }}.
{% else %}
Nothing in particular.
{% endif %}
