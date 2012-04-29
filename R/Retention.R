#' Estimates cohort retention.
#' 
cohortDetails <- function(students, grads, 
						  studentIdColumn='CONTACT_ID_SEQ',
						  degreeColumn='DEGREE_CODE',
						  persistColumn='PERSIST_FLAG',
						  warehouseDateColumn='CREATED_DATE', 
						  gradColumn='START_DATE',
						  min.cell.size=5) {
	students = students[order(students[,warehouseDateColumn], na.last=FALSE),]
	
	firstWHDate = min(students[,warehouseDateColumn], na.rm=TRUE)
    lastWHDate = max(students[,warehouseDateColumn], na.rm=TRUE)
    last = students[which(students[,warehouseDateColumn] == lastWHDate),]
    
    students[,persistColumn] = NULL
    
    grads = grads[which(as.Date(grads[,gradColumn]) < lastWHDate),]
    
    #This will leave only the first occurance of a student in a particular degree code
    students = students[!duplicated(students[,c(studentIdColumn, degreeColumn)]),]
    #By finding duplicates starting at the end, the first occurance will have the
    #Transferred value set to true
    students$Transferred = FALSE
    rows = duplicated(students[,studentIdColumn], fromLast=TRUE)
    if(nrow(students[rows,]) > 0 ) { 
        students[rows,]$Transferred = TRUE
        #We can now remove duplciated students, the remaining data frame contains 
        #the students' first enrollment
        students = students[!duplicated(students[,studentIdColumn], fromLast=FALSE),]
    }
    #Merge in graduates
    students = merge(students, grads[,c(studentIdColumn, gradColumn)], 
    				 by=c(studentIdColumn), all.x=TRUE)
    #If the START_DATE is not NA, then the student graduated. Note that this does
    #not mean they graduated from their initial DEGREE_CODE (see merge above
    #matches only on CONTACT_ID_SEQ)
    students$Graduated = FALSE
    gr = !is.na(students[,gradColumn]) & !is.na(students[,warehouseDateColumn]) & 
    			students[,gradColumn] >= students[,warehouseDateColumn]
    gr[is.na(gr)] = FALSE #TODO: How are the NAs?s
    if(nrow(students[gr,]) > 0) {
        students[gr,]$Graduated = TRUE
    }
    #See if the student is still enrolled as of the last cohort
    last$StillEnrolled = TRUE
    students = merge(students, last[,c(studentIdColumn, 'StillEnrolled', persistColumn)], 
    				 by=c(studentIdColumn), all.x=TRUE)
    se = is.na(students$StillEnrolled)
    if(nrow(students[se,]) > 0) {
        students[se,]$StillEnrolled = FALSE
    }
    #Remove the baseline data
    students = students[!is.na(students[,warehouseDateColumn]),]
    #Remove the first and last cohort month
    if(length(which(students[,warehouseDateColumn] == firstWHDate)) > 0) {
    	students = students[-which(students[,warehouseDateColumn] == firstWHDate),]    	
    }
    if(length(which(students[,warehouseDateColumn] == lastWHDate)) > 0) {
	    students = students[-which(students[,warehouseDateColumn] == lastWHDate),]
    }
    if(nrow(students) < min.cell.size) {
        return(NULL)
    }
    #Create the status variable that we will plot with
    students$Status = factor('Withdrawn', levels=c('Graduated', 'Graduated Other', 
    								'Still Enrolled', 'Transferred', 'Withdrawn' ))
    if(length(which(students$StillEnrolled) == TRUE) > 0) {
        students[students$StillEnrolled,]$Status = 'Still Enrolled'
    }
    if(length(which(students$StillEnrolled == TRUE & students$Transferred == TRUE)) > 0) {
        students[students$StillEnrolled & students$Transferred,]$Status = 'Transferred'
    }
    if(length(which(students$Graduated == TRUE)) > 0) {
        students[students$Graduated,]$Status = 'Graduated'
    }
    if(length(which(students$Transferred == TRUE & students$Graduated == TRUE)) > 0) {
        students[students$Graduated & students$Transferred,]$Status = 'Graduated Other'
    }
    
    #Are those who are still enrolled persisting?
    persistData = students[,persistColumn]
    students[,persistColumn] = NULL
    students$Persisting = as.logical(NA)
	persistingYes = which(students$Status %in% c('Still Enrolled', 'Transferred') & 
							persistData)
	if(length(persistingYes) > 0) {
		students[persistingYes,]$Persisting = TRUE
	}
	persistingNo = which(students$Status %in% c('Still Enrolled', 'Transferred') & 
							!persistData)
	if(length(persistingNo) > 0) {
		students[persistingNo,]$Persisting = FALSE
	}
    
    students$Month = as.factor(format(students[,warehouseDateColumn], format='%Y-%m'))
    
    students$Months = (mondf(students[,warehouseDateColumn], lastWHDate))
    
    return(students)
}

#' 
#' @export
studentDetails <- function(students, grads, months=c(15,24), ...) {
	cohorts = unique(students[!is.na(students[,warehouseDateColumn]),warehouseDateColumn])
	
	results <- data.frame()
	for(i in length(cohorts):3) {
		result = cohortDetails(students, grads, ...)
		if(!is.null(result)) {
			result = result[result$Months %in% months,]
			if(nrow(result) > 0) {
				results = rbind(results, result)
			}
		}
		remove = -which(students[,warehouseDateColumn] == cohorts[i])
		if(length(remove) > 0) {
			students = students[remove,]
		}
	}
	return(results)
}


#' Estimates cohort retention.
#' 
#' @export
cohortRetention <- function(students, grads, 
							studentIdColumn='CONTACT_ID_SEQ',
							degreeColumn='DEGREE_CODE',
							persistColumn='PERSIST_FLAG',
							warehouseDateColumn='CREATED_DATE', 
							gradColumn='START_DATE',
							grouping=NULL, ...) {
	cr = list()
	cr$studentIdColumn = studentIdColumn
	cr$degreeColumn = degreeColumn
	cr$persistColumn = persistColumn
	cr$warehouseDateColumn = warehouseDateColumn
	cr$gradColumn = gradColumn
	cr$grouping = grouping
	cr$ComparisonCohort = max(students[,warehouseDateColumn], na.rm=TRUE)

	students <- cohortDetails(students, grads, 
							  studentIdColumn=studentIdColumn,
							  degreeColumn=degreeColumn,
							  persistColumn=persistColumn,
							  warehouseDateColumn=warehouseDateColumn,
							  gradColumn=gradColumn,
							  ...)
	cr$Students = students
	
	buildSummary <- function(s) {
		t = as.data.frame(table(s$Month, s$Status))
	 	if(!('Var1' %in% names(t) & 'Var2' %in% names(t))) {
	 		return(NULL)
	 	}
	  
	    t = cast(t, Var1 ~ Var2, value='Freq')
	    totals = apply(t[,2:ncol(t)], 1, sum)
	    t[,2:ncol(t)] = 100 * t[,2:ncol(t)] / totals
	    GraduationRate = apply(t[,2:3], 1, sum)
	    RetentionRate = apply(t[,2:5], 1, sum)
	    t = melt(t, id='Var1')
	    rownames(t) = 1:nrow(t)
	    
  		t2 = as.data.frame(table(s$Month, s$Persisting))
	 	if(!('Var1' %in% names(t2) & 'Var2' %in% names(t2))) {
	 		return(NULL)
	 	}
  		t2 = cast(t2, Var1 ~ Var2, value='Freq')
	 	if(!'TRUE' %in% names(t2)) {
	 		t2[,'TRUE'] = 0
	 	}
	 	if(!'FALSE' %in% names(t2)) {
	 		t2[,'FALSE'] = 0
	 	}
	    totals2 = apply(t2[,2:3], 1, sum)
	    t2[,2:3] = 100 * t2[,2:3] / totals2
	    PersistenceRate = t2[,'TRUE']
	    
	 	if('Var1' %in% names(t) & 'Var2' %in% names(t)) {
		    summary = cast(t, Var1 ~ Var2, value='value')
		    summary = cbind(summary, GraduationRate, RetentionRate, PersistenceRate, totals)
		    names(summary)[1] = 'Cohort'
		    names(summary)[ncol(summary)] = 'Enrollments'
	 
		 	return(summary)
	 	} else {
	 		return(NULL)
	 	}
	}
	
	results = data.frame()
	
	if(is.null(grouping)) {
		results = buildSummary(students)
	} else {
		groups = unique(students[,grouping])
  		for(g in groups) {
  			s = students[which(students[,grouping] == g),]
	 		if(nrow(s) > 20) {
		 		r = buildSummary(s)
	 			if(!is.null(r)) {
			 		r$Group = g
			 		results = rbind(results, r)
	 			}
	 		}
  		}
	}
	
	cr$summary = results
	class(cr) = "CohortRetention"
	
    return(cr)
}


#' Estimates retention.
#' 
#' @export
retention <- function(students, grads, ...) {
    cohorts = unique(students[!is.na(students[,warehouseDateColumn]),warehouseDateColumn])
    
    results <- list()
    for(i in length(cohorts):3) {
        result = cohortRetention(students, grads, ...)
        if(!is.null(result$summary)) {
            results[[as.character(cohorts[i])]] = result$summary
        }
        remove = -which(students[,warehouseDateColumn] == cohorts[i])
        if(length(remove) > 0) {
            students = students[remove,]
        }
    }
    
    if(length(results) == 0) {
        return(NULL)
    }
    
	cols = c('Cohort', 'GraduationRate', 'RetentionRate', 'PersistenceRate', 
			 'Enrollments', 'Graduated','Graduated Other','Still Enrolled','Transferred')
	if('Group' %in% names(results[[1]])) {
		cols = c(cols, 'Group')
	}
	
	long2 = results[[1]][,cols]
	long2$Month = (mondf(as.Date(paste(long2$Cohort, '01', sep='-')), 
						 as.Date(paste(names(results)[1], '01', sep='-')) ))
	long2$Comparison = names(results)[1]
    for(i in 2:length(results)) {
    	if(nrow(results[[i]]) > 0 & ncol(results[[i]]) > 0) {
	        l = results[[i]][,cols]
			l$Month = (mondf(as.Date(paste(l$Cohort, '01', sep='-')), 
							 as.Date(paste(names(results)[i], '01', sep='-')) ))
			l$Comparison = names(results)[i]
	    	long2 = rbind(long2, l)
    	}
    }
    
    class(long2) = 'Retention'
    return(long2)
}

monnb <- function(d) { 
	lt <- as.POSIXlt(as.Date(d, origin="1900-01-01"))
	lt$year*12 + lt$mon
} 

mondf <- function(d1, d2) { 
	monnb(d2) - monnb(d1)
}

