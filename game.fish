#!/usr/bin/env fish

set -g width 10
set -g height 10
set -g num_mines 12

set -g orig_stty (stty -g)

function restore_term --on-event fish_exit
    stty $orig_stty 2>/dev/null
    printf "\e[?25h\e[?1049l"
end

function handle_interrupt --on-signal INT --on-signal TERM
    restore_term
    exit 130
end

function handle_resize --on-signal WINCH
    printf "\e[2J\e[H"
    draw_board
end

function init_game
    set -g cx 1
    set -g cy 1
    set -g first_move 1
    set -g game_over 0
    set -g game_won 0
    set -g exploded_idx 0
    set -g revealed_count 0
    set -g flags_placed 0

    set -g mines
    set -g counts
    set -g state

    set -l total (math "$width * $height")
    for i in (seq 1 $total)
        set -a mines 0
        set -a counts 0
        set -a state hidden
    end
end

function place_mines -a safe_x safe_y
    set -l candidates
    set -l idx 0
    for y in (seq 1 $height)
        for x in (seq 1 $width)
            set idx (math "$idx + 1")
            if test (math "abs($x - $safe_x)") -gt 1; or test (math "abs($y - $safe_y)") -gt 1
                set -a candidates $idx
            end
        end
    end

    for m in (seq 1 $num_mines)
        set -l pick (random 1 (count $candidates))
        set -l mine_idx $candidates[$pick]
        set -g mines[$mine_idx] 1
        set -e candidates[$pick]
    end

    set idx 0
    for y in (seq 1 $height)
        for x in (seq 1 $width)
            set idx (math "$idx + 1")
            if test $mines[$idx] -eq 1
                continue
            end
            set -l count 0
            for dy in -1 0 1
                for dx in -1 0 1
                    if test $dx -eq 0; and test $dy -eq 0
                        continue
                    end
                    set -l nx (math "$x + $dx")
                    set -l ny (math "$y + $dy")
                    if test $nx -ge 1; and test $nx -le $width; and test $ny -ge 1; and test $ny -le $height
                        set -l nidx (math "($ny - 1) * $width + $nx")
                        if test $mines[$nidx] -eq 1
                            set count (math "$count + 1")
                        end
                    end
                end
            end
            set -g counts[$idx] $count
        end
    end
end

function reveal_cell -a sx sy
    if test $first_move -eq 1
        place_mines $sx $sy
        set -g first_move 0
    end

    set -l start_idx (math "($sy - 1) * $width + $sx")

    if test "$state[$start_idx]" = flagged
        return
    end

    if test "$state[$start_idx]" = revealed
        set -l needed $counts[$start_idx]
        if test $needed -gt 0
            set -l adj_flags 0
            set -l hidden_neighbors
            for dy in -1 0 1
                for dx in -1 0 1
                    if test $dx -eq 0; and test $dy -eq 0
                        continue
                    end
                    set -l nx (math "$sx + $dx")
                    set -l ny (math "$sy + $dy")
                    if test $nx -ge 1; and test $nx -le $width; and test $ny -ge 1; and test $ny -le $height
                        set -l nidx (math "($ny - 1) * $width + $nx")
                        if test "$state[$nidx]" = flagged
                            set adj_flags (math "$adj_flags + 1")
                        else if test "$state[$nidx]" = hidden
                            set -a hidden_neighbors "$nx,$ny"
                        end
                    end
                end
            end
            if test $adj_flags -eq $needed
                for pos in $hidden_neighbors
                    set -l xy (string split "," $pos)
                    reveal_cell $xy[1] $xy[2]
                end
            end
        end
        return
    end

    if test $mines[$start_idx] -eq 1
        set -g game_over 1
        set -g exploded_idx $start_idx
        return
    end

    set -g state[$start_idx] revealed
    set -g revealed_count (math "$revealed_count + 1")

    set -l queue
    if test $counts[$start_idx] -eq 0
        set -a queue $start_idx
    end

    while test (count $queue) -gt 0
        set -l curr $queue[1]
        set -e queue[1]

        set -l y (math "floor(($curr - 1) / $width) + 1")
        set -l x (math "(($curr - 1) % $width) + 1")

        for dy in -1 0 1
            for dx in -1 0 1
                if test $dx -eq 0; and test $dy -eq 0
                    continue
                end
                set -l nx (math "$x + $dx")
                set -l ny (math "$y + $dy")
                if test $nx -ge 1; and test $nx -le $width; and test $ny -ge 1; and test $ny -le $height
                    set -l nidx (math "($ny - 1) * $width + $nx")
                    if test "$state[$nidx]" = hidden; and test $mines[$nidx] -eq 0
                        set -g state[$nidx] revealed
                        set -g revealed_count (math "$revealed_count + 1")
                        if test $counts[$nidx] -eq 0
                            set -a queue $nidx
                        end
                    end
                end
            end
        end
    end

    set -l safe_total (math "$width * $height - $num_mines")
    if test $revealed_count -ge $safe_total
        set -g game_won 1
        set -l total (math "$width * $height")
        for i in (seq 1 $total)
            if test $mines[$i] -eq 1
                set -g state[$i] flagged
            end
        end
        set -g flags_placed $num_mines
    end
end

function toggle_flag -a x y
    set -l idx (math "($y - 1) * $width + $x")
    if test "$state[$idx]" = hidden
        set -g state[$idx] flagged
        set -g flags_placed (math "$flags_placed + 1")
    else if test "$state[$idx]" = flagged
        set -g state[$idx] hidden
        set -g flags_placed (math "$flags_placed - 1")
    end
end

function set_num_color -a n
    switch $n
        case 1
            set_color --bold brcyan
        case 2
            set_color --bold green
        case 3
            set_color --bold red
        case 4
            set_color --bold magenta
        case 5
            set_color --bold yellow
        case 6
            set_color --bold cyan
        case 7
            set_color --bold white
        case 8
            set_color brblack
    end
end

function draw_board
    printf "\e[H\e[2K"
    set -l remaining (math "$num_mines - $flags_placed")

    set_color --bold cyan
    printf "MINESWEEPER | Mines left: %s " $remaining
    set_color normal
    printf "\n\e[2K"
    printf "Arrows/WASD: Move | G: Explode/Dig | F: Flag | R: Restart | Q: Quit"
    printf "\n\e[2K"

    set_color brblack
    printf " +"
    for x in (seq 1 $width)
        printf -- "---"
    end
    printf "+"
    set_color normal
    printf "\n\e[2K"

    set -l idx 0
    for y in (seq 1 $height)
        set_color brblack
        printf " |"
        set_color normal

        for x in (seq 1 $width)
            set idx (math "$idx + 1")
            set -l selected 0
            if test $x -eq $cx; and test $y -eq $cy
                set selected 1
            end

            set -l left_pad " "
            set -l right_pad " "
            if test $selected -eq 1
                set left_pad "["
                set right_pad "]"
            end

            if test $selected -eq 1
                set_color --bold brcyan
                printf "%s" $left_pad
                set_color normal
            else
                printf "%s" $left_pad
            end

            if test $game_over -eq 1; and test $mines[$idx] -eq 1
                if test $idx -eq $exploded_idx
                    set_color --bold white -b red
                    printf "X"
                else
                    set_color --bold red
                    printf "*"
                end
            else if test "$state[$idx]" = flagged
                set_color --bold yellow
                printf "F"
            else if test "$state[$idx]" = hidden
                set_color brblack
                printf "#"
            else
                set -l c $counts[$idx]
                if test $c -eq 0
                    set_color brblack
                    printf "."
                else
                    set_num_color $c
                    printf "%s" $c
                end
            end
            set_color normal

            if test $selected -eq 1
                set_color --bold brcyan
                printf "%s" $right_pad
                set_color normal
            else
                printf "%s" $right_pad
            end
        end

        set_color brblack
        printf "|"
        set_color normal
        printf "\n\e[2K"
    end

    set_color brblack
    printf " +"
    for x in (seq 1 $width)
        printf -- "---"
    end
    printf "+"
    set_color normal
    printf "\n\e[2K"

    if test $game_over -eq 1
        set_color --bold red
        printf " BOOM! You exploded a mine! Press [R] to play again or [Q] to quit."
        set_color normal
    else if test $game_won -eq 1
        set_color --bold green
        printf " YOU WIN! All safe squares cleared! Press [R] to play again or [Q] to quit."
        set_color normal
    end
    printf "\e[J"
end

function read_key
    stty -icanon -echo min 1 time 0
    set -l k (dd bs=1 count=1 2>/dev/null)

    if test (count $k) -eq 0
        echo enter
        return
    end

    if test "$k" = \e
        stty -icanon -echo min 0 time 1
        set -l s1 (dd bs=1 count=1 2>/dev/null)
        set -l s2 (dd bs=1 count=1 2>/dev/null)
        stty -icanon -echo min 1 time 0

        if test "$s1" = "["; or test "$s1" = O
            switch $s2
                case A
                    echo up
                    return
                case B
                    echo down
                    return
                case C
                    echo right
                    return
                case D
                    echo left
                    return
            end
        end
        echo esc
        return
    end

    echo (string lower -- "$k")
end

printf "\e[?1049h\e[?25l\e[2J\e[H"
init_game

while true
    draw_board
    set -l key (read_key)

    switch $key
        case up w
            if test $cy -gt 1
                set -g cy (math "$cy - 1")
            end
        case down s
            if test $cy -lt $height
                set -g cy (math "$cy + 1")
            end
        case left a
            if test $cx -gt 1
                set -g cx (math "$cx - 1")
            end
        case right d
            if test $cx -lt $width
                set -g cx (math "$cx + 1")
            end
        case g
            if test $game_over -eq 0; and test $game_won -eq 0
                reveal_cell $cx $cy
            end
        case f
            if test $game_over -eq 0; and test $game_won -eq 0
                toggle_flag $cx $cy
            end
        case r
            printf "\e[2J\e[H"
            init_game
        case q
            break
    end
end
