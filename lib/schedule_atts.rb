# via https://github.com/zpearce/Schedule-Attributes/raw/master/lib/schedule_atts.rb

require 'ice_cube'
require 'active_support'
require 'active_support/time_with_zone'
require 'ostruct'

module ScheduleAtts
  DAY_NAMES = Date::DAYNAMES.map(&:downcase).map(&:to_sym)
  WEEKDAYS = {:monday=>1, :tuesday=>2, :wednesday=>3, :thursday=>4, :friday=>5}

  def schedule
    @schedule ||= begin
      if schedule_yaml.blank?
        IceCube::Schedule.new(Date.today.to_time).tap{ |sched| sched.add_recurrence_rule(IceCube::Rule.daily) }
      else
        IceCube::Schedule.from_yaml(schedule_yaml)
      end
    end
  end

  def schedule_attributes=(options)
    options = options.dup
    options[:interval] = options[:interval].to_i
    options[:start_date] &&= ScheduleAttributes.parse_in_timezone(options[:start_date])
    options[:date]       &&= ScheduleAttributes.parse_in_timezone(options[:date])
    options[:until_date] &&= ScheduleAttributes.parse_in_timezone(options[:until_date])

    if options[:repeat].to_i == 0
      @schedule = IceCube::Schedule.new(options[:date])
      @schedule.add_recurrence_time(options[:date])
    else
      @schedule = IceCube::Schedule.new(options[:start_date])

      rule = case options[:interval_unit]
             when 'day'
               IceCube::Rule.daily options[:interval]
             when 'week'
               # TODO: should add test for it.
               if (options.keys.map(&:to_sym) & DAY_NAMES).empty?
                 IceCube::Rule.weekly(options[:interval])
               else
                 IceCube::Rule.weekly(options[:interval]).day( *IceCube::TimeUtil::DAYS.keys.select{|day| options[day].to_i == 1 } )
               end
             # TODO: should add test for it
             when 'weekdays'
               IceCube::Rule.weekly(options[:interval]).day( *WEEKDAYS.keys)
             when 'month'
               if options[:by_day_of].blank?
                 IceCube::Rule.monthly options[:interval]
               elsif options[:by_day_of] == 'month'
                 IceCube::Rule.monthly(options[:interval]).day_of_month(options[:day_of_month].to_i)
               elsif options[:by_day_of] == 'week'
                 # schedule.add_recurrence_rule Rule.monthly.day_of_week(:tuesday => [1, -1])
                 # every month on the first and last tuesdays of the month
                 IceCube::Rule.monthly(options[:interval]).day_of_week(options[:day_of_week].to_sym => [options[:day_of_month].to_i])
               end
             when 'year'
                IceCube::Rule.yearly(options[:interval]).month_of_year(options[:start_date].month).day_of_month(options[:start_date].day)
             end

      rule.until(options[:until_date]) if options[:until_date].present?

      @schedule.add_recurrence_rule(rule)
    end

    self.schedule_yaml = @schedule.to_yaml
  end

  def schedule_attributes
    atts = {}

    if rule = schedule.rrules.first
      atts[:repeat]     = 1
      atts[:start_date] = schedule.start_time.to_date
      atts[:date]       = Date.today # for populating the other part of the form

      rule_hash = rule.to_hash
      atts[:interval] = rule_hash[:interval]

      case rule
      when IceCube::DailyRule
        atts[:interval_unit] = 'day'
      when IceCube::WeeklyRule
        atts[:interval_unit] = 'week'

        if rule_hash[:validations][:day]
          # TODO: should add test for it.
          if rule_hash[:validations][:day] == WEEKDAYS.values
            atts[:interval_unit] = 'weekdays'
          end
          rule_hash[:validations][:day].each do |day_idx|
            atts[ DAY_NAMES[day_idx] ] = 1
          end
        end
      when IceCube::MonthlyRule
        atts[:interval_unit] = 'month'
        atts[:repeat]     = 2

        day_of_week = rule_hash[:validations][:day_of_week]
        day_of_month = rule_hash[:validations][:day_of_month]

        if day_of_week
          day_of_week = day_of_week.first.flatten
          atts[:day_of_week] = DAY_NAMES[day_of_week.first]
          atts[:day_of_month] = day_of_week[1]
          atts[:by_day_of] = 'week'
        elsif day_of_month
          atts[:day_of_month] = day_of_month.first
          atts[:by_day_of] = 'month'
        else
          atts[:repeat]     = 1
        end
      end

      if rule.until_time
        atts[:until_date] = rule.until_time.to_date
      end
    else
      atts[:repeat]     = 0
      atts[:date]       = schedule.start_time.to_date
      atts[:start_date] = Date.today # for populating the other part of the form
    end

    OpenStruct.new(atts)
  end

  def self.parse_in_timezone(str)
    if Time.respond_to?(:zone) && Time.zone
      Time.zone.parse(str)
    else
      Time.parse(str)
    end
  end
end

ScheduleAttributes = ScheduleAtts

class IceCube::Rule
  def ==(other)
    to_hash == other.to_hash
  end
end

class IceCube::Schedule
  def ==(other)
    to_hash == other.to_hash
  end
end
